#import <Foundation/Foundation.h>
#import "LayoutBus.h"
#include <assert.h>
#include <stdio.h>
int main(int argc,const char **argv){
 @autoreleasepool{
  if(argc==3 && strcmp(argv[1],"read")==0){
   NSString *bundle=[NSString stringWithUTF8String:argv[2]];
   CGRect local;double overlap=0;
   assert(STHReadLayout(bundle,CGRectMake(0,0,400,800),&local,&overlap));
   assert(fabs(overlap-500)<.01&&fabs(local.origin.y-300)<.01);
   return 0;
  }
  NSString *bundle=[@"test.stheno." stringByAppendingString:NSUUID.UUID.UUIDString];
  assert(STHBeginLayout(bundle));assert(STHLayoutStatus(bundle)==2);
  CGRect pending;double amount=0;
  assert(!STHReadLayout(bundle,CGRectMake(0,0,400,800),&pending,&amount));
  assert(STHPublishLayout(bundle,CGRectMake(100,400,200,400),CGRectMake(0,550,400,300),YES));
  NSTask *reader=[NSTask new];reader.executableURL=[NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]];
  reader.arguments=@[@"read",bundle];NSError *error=nil;
  assert([reader launchAndReturnError:&error]);[reader waitUntilExit];assert(reader.terminationStatus==0);
  assert(STHLayoutStatus(bundle)==1);
  // Repeated silent heartbeats and slot flips must always leave a readable
  // committed pair; no periodic invalidation/scope fallback to legacy inset.
  for(int i=0;i<200;i++){
   double top=(i&1)?550:560;
   assert(STHPublishLayout(bundle,CGRectMake(100,400,200,400),CGRectMake(0,top,400,850-top),YES));
   CGRect local;double overlap=0;
   assert(STHLayoutStatus(bundle)==1&&STHReadLayout(bundle,CGRectMake(0,0,400,800),&local,&overlap));
   assert(fabs(overlap-(800-(top-400)*2))<.01);
  }
  assert(STHPublishLayout(bundle,CGRectZero,CGRectZero,NO));
  CGRect local;double overlap=0;
  assert(!STHReadLayout(bundle,CGRectMake(0,0,400,800),&local,&overlap));
  puts("Cross-process layout transport passed (separate reader executable and hide invalidation)");
 }
 return 0;
}
