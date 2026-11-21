#import <Foundation/Foundation.h>
#include <assert.h>
#include <unistd.h>
#include <string.h>
#import <notify.h>
static int stateReads;
static uint32_t countedStateRead(int token,uint64_t *value){stateReads++;return notify_get_state(token,value);}
#define notify_get_state countedStateRead
#import "KeyboardFocusBus.m"
#undef notify_get_state
static void same(STHRect a,STHRect b){assert(fabs(a.x-b.x)<.5&&fabs(a.y-b.y)<.5&&fabs(a.w-b.w)<.5&&fabs(a.h-b.h)<.5);}
int main(int argc,const char **argv){@autoreleasepool{
 if(argc==4&&strcmp(argv[1],"child")==0){
  NSString *a=@(argv[2]),*b=@(argv[3]);
  for(int i=0;i<200;i++){assert(STHPublishInputKeyboard(a,(STHRect){0,510,400,340}));assert(STHPublishInputKeyboard(b,(STHRect){0,550,400,300}));STHPublishInputFocus(a,NO);}
  assert(write(STDOUT_FILENO,"R",1)==1);char signal;assert(read(STDIN_FILENO,&signal,1)==1);return 0;
 }
 NSString *a=[@"stheno.snapshot.a." stringByAppendingString:NSUUID.UUID.UUIDString];
 NSString *b=[@"stheno.snapshot.b." stringByAppendingString:NSUUID.UUID.UUIDString];
 STHRect f={0,550,400,300},out={0};STHPublishInputFocus(a,YES);assert(STHReadInputFocus(a)&&!STHReadInputKeyboard(a,&out));
 for(int i=0;i<200;i++){
  assert(STHPublishInputKeyboard(a,f));assert(STHReadInputKeyboard(a,&out));same(f,out);
  stateReads=0;assert(STHReadInputFocusSnapshot(a,&out));same(f,out);assert(stateReads==5);
  stateReads=0;assert(STHReadInputFocusSnapshot(a,NULL));assert(stateReads==4);
  uint64_t fresh=0;assert(!notify_get_state(token(leaseName(a)),&fresh));
  uint64_t aged=(fresh&0xffff000000000000ULL)|((inputNow()-900)&0x0000ffffffffffffULL);
  assert(!notify_set_state(token(leaseName(a)),aged));assert(STHReadInputFocusSnapshot(a,&out));assert(out.w==0&&out.h==0);
  assert(!STHReadInputKeyboard(a,&out));assert(!notify_set_state(token(leaseName(a)),fresh));
  inputReadFloor=inputNow()+1;assert(!STHReadInputKeyboard(a,&out));inputReadFloor=0;
  uint64_t commit=0;assert(!notify_get_state(token(leaseName(a)),&commit));
  // An incomplete inactive-slot write must not change the committed pair.
  int inactive=frameToken(a,(commit&(1ULL<<62))?@"frame0":@"frame1");uint64_t other;assert(STHPackRect((STHRect){0,500,400,350},&other));
  assert(!notify_set_state(inactive,other));assert(STHReadInputKeyboard(a,&out));same(f,out);
  assert(STHPublishInputKeyboard(b,(STHRect){0,510,400,340}));STHPublishInputFocus(a,NO);
  assert(!STHReadInputKeyboard(a,&out)&&STHReadInputKeyboard(b,&out));same(out,(STHRect){0,510,400,340});
  assert(!STHPublishInputKeyboard(a,(STHRect){0,840,400,10}));assert(STHReadInputFocus(b));
  STHPublishInputFocus(b,NO);assert(!STHReadInputFocus(b));
 }
 frameToken(b,@"frame0");frameToken(b,@"frame1");token(leaseName(a));token(leaseName(b));
 NSTask *child=[NSTask new];NSPipe *input=[NSPipe pipe],*ready=[NSPipe pipe];
 child.launchPath=NSProcessInfo.processInfo.arguments[0];child.arguments=@[@"child",a,b];child.standardInput=input;child.standardOutput=ready;
 __block BOOL complete=NO;
 STHObserveInputFocus(^{
  STHRect received;if(complete||!STHReadInputKeyboard(b,&received))return;
  complete=YES;same(received,(STHRect){0,550,400,300});assert(!STHReadInputFocus(a));
  [input.fileHandleForWriting writeData:[@"X" dataUsingEncoding:NSUTF8StringEncoding]];[child waitUntilExit];assert(child.terminationStatus==0);
  puts("Input snapshots: 200 paired/partial-write/handoff cases and 200 real cross-process coalesced updates; no mixed frame or stale A hide clearing B");fflush(stdout);exit(0);
 });
 [child launch];assert([ready.fileHandleForReading readDataOfLength:1].length==1);
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{assert(0&&"snapshot callback timeout");});
 dispatch_main();
}return 0;}
