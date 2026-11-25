#define STH_VIEWPORT_HOST_TEST 1
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <assert.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <dispatch/dispatch.h>
// Import the production Host, but capture every delayed callback. The fake
// clock must execute them later on an empty animation stack, just like GCD.
static dispatch_time_t STHVHostTestTime(dispatch_time_t base,int64_t delta);
static void STHVHostTestAfter(dispatch_time_t when,dispatch_queue_t queue,dispatch_block_t block);
#define dispatch_time STHVHostTestTime
#define dispatch_after STHVHostTestAfter
#import "ViewportHost.m"
#undef dispatch_after
#undef dispatch_time
@interface DeferredHostWork:NSObject
@property dispatch_time_t deadline;
@property(copy) dispatch_block_t block;
@end
@implementation DeferredHostWork @end
static NSMutableArray<DeferredHostWork *> *delayed;
@interface Card:NSObject
@property(copy) NSString *bundle;
@property double scale;
@property CGSize offset;
@property BOOL minimized;
@end
@implementation Card @end
@interface Packet:NSObject
@property BOOL active,keyboardVisible,hosted;
@property STHVRect card,keyboard;
@property uint64_t event,physicalGeneration;
@end
@implementation Packet @end
static NSArray<Card *> *cards;
static NSMutableDictionary<NSString *,Packet *> *requests,*layouts;
static uint64_t offeredKey,events;
static double now;
static BOOL enabled=YES,unavailable,registryMissing,oversized;
static NSUInteger awakeCount;
void STHScreenAwakeUpdate(NSUInteger n){awakeCount=n;}
BOOL STHScreenAwakeHeld(void){return awakeCount>0;}
static STHVRect testScreen={0,0,400,850},realKeys={0,550,400,300};
static int writes,transaction,interruptions,refreshes,animationCalls,maxTransactionDepth;
static const char *delayedScenario="lifecycle";
static dispatch_time_t testTime(double value){return (dispatch_time_t)llround(value*NSEC_PER_SEC);}
static dispatch_time_t STHVHostTestTime(dispatch_time_t base,int64_t delta){assert(base==DISPATCH_TIME_NOW&&delta>=0);return testTime(now)+(uint64_t)delta;}
static void STHVHostTestAfter(dispatch_time_t when,dispatch_queue_t queue,dispatch_block_t block){
 assert(delayed&&queue==dispatch_get_main_queue()&&when>=testTime(now));
 DeferredHostWork *work=[DeferredHostWork new];work.deadline=when;work.block=block;[delayed addObject:work];
}
static void advanceHost(double target){
 assert(!transaction&&target>=now);
 dispatch_time_t deadline=testTime(target);
 for(;;){
  DeferredHostWork *next=nil;
  for(DeferredHostWork *work in delayed)if(work.deadline<=deadline&&(!next||work.deadline<next.deadline))next=work;
  if(!next)break;
  [delayed removeObjectIdenticalTo:next];now=next.deadline/(double)NSEC_PER_SEC;
  assert(NSThread.isMainThread&&transaction==0);next.block();assert(transaction==0);
 }
 now=target;
}
STHVRect STHVHostTestScreen(void){return testScreen;}
double STHVHostTestNow(void){return now;}
BOOL STHSystemActionRuntimeReady(void){return YES;}
BOOL STHSystemActionsEnabled(void){return enabled;}
void *STHDockCopyFloating(void){return registryMissing?NULL:(__bridge void *)cards;}
size_t STHChooserManagersCount(void *p){return oversized?5000:[(__bridge NSArray *)p count];}
void *STHChooserCopyManagerAt(size_t i,void *p){return (__bridge void *)[(__bridge NSArray *)p objectAtIndex:i];}
void STHChooserReleaseArray(void *p){}
void STHChooserReleaseSwift(void *p){}
void *STHSystemCopyModelIdentifier(void *p){return (__bridge_retained void *)((__bridge Card *)p).bundle;}
BOOL STHNativeMinimized(void *p){return ((__bridge Card *)p).minimized;}
NSUInteger STHNativeOrientation(void *p){return 1;}
CGRect STHNativeRect(void *p){Card *c=(__bridge Card *)p;double h=testScreen.w==430?731:625;return CGRectMake(testScreen.w/2+c.offset.width-testScreen.w*c.scale/2,testScreen.h/2+c.offset.height-h*c.scale/2,testScreen.w*c.scale,h*c.scale);}
double STHNativeGetScale(void *p){return ((__bridge Card *)p).scale;}
CGSize STHNativeGetOffset(void *p){return ((__bridge Card *)p).offset;}
void STHNativeSetViewportGeometry(void *p,const double *g){
 // Negative CI must observe THIS old-callback defect, not merely any crash.
 if(transaction!=1){fprintf(stderr,"STHV_HOST_TRANSACTION_VIOLATION:%s:STHNativeSetViewportGeometry:depth=%d\n",delayedScenario,transaction);abort();}
 Card *c=(__bridge Card *)p;c.scale=g[0];c.offset=CGSizeMake(g[1],g[2]);writes++;
}
void STHNativeRefreshGeometry(void *p){refreshes++;}
void STHCenterRunAnimation(void (^block)(void),int style){
 assert(style==0&&transaction==0);animationCalls++;transaction++;
 if(transaction>maxTransactionDepth)maxTransactionDepth=transaction;
 @try{block();}@finally{assert(transaction==1);transaction--;}
}
void STHGestureInputFocusChanged(void *p){interruptions++;}
uint64_t STHVKey(NSString *b){return [b isEqual:@"a"]?11:([b isEqual:@"b"]?22:33);}
uint64_t STHVRequestOwner(void){if(unavailable)return 0;for(NSString *b in requests)if(STHVKey(b)==offeredKey&&requests[b].active)return offeredKey;return 0;}
BOOL STHVReadRequest(NSString *b,STHVSnapshot *s){Packet *p=requests[b];if(unavailable||!p)return NO;if(s)*s=(STHVSnapshot){.active=p.active,.keyboard=p.keyboard,.owner=STHVKey(b),.event=p.event};return YES;}
BOOL STHVPublishLayoutPolicyState(NSString *b,BOOL active,STHVRect card,STHVRect physical,uint64_t generation,BOOL visible,BOOL reflow){assert(!active||(visible&&generation));Packet *p=[Packet new];p.active=active;p.card=card;p.keyboard=physical;p.physicalGeneration=generation;p.keyboardVisible=visible;p.hosted=STHVValid(card);layouts[b]=p;return YES;}
BOOL STHVReadClientFrames(NSString *b,STHVSnapshot *out){return NO;}
BOOL STHVReadProbe(NSString *b,STHVRect *a,STHVRect *p){return NO;}
NSDictionary *STHVRectJSON(STHVRect r){return @{@"x":@(r.x),@"y":@(r.y),@"w":@(r.w),@"h":@(r.h)};}
void STHVLog(NSString *e,NSString *b,NSDictionary *v){}
void STHVLogInstallRelay(void){}
static Card *make(NSString *b){Card *c=[Card new];c.bundle=b;c.scale=.8;return c;}
static void claim(NSString *b,BOOL active,STHVRect raw){Packet *p=[Packet new];p.active=active;p.keyboard=raw;p.event=++events;requests[b]=p;if(active)offeredKey=STHVKey(b);}
static void registry(void){STHCenterRunAnimation(^{updateRegistry(YES);},0);}
static void sampleFrame(STHVRect frame,BOOL hide){
 int calls=animationCalls;
 STHCenterRunAnimation(^{STHViewportPhysicalWill(cr(frame),hide);},0);
 assert(transaction==0&&animationCalls==calls+1); // Never wrap a synchronous native entry twice.
}
static void sample(BOOL hide){sampleFrame(realKeys,hide);}
static Card *newDelayedScenario(void){
 sample(YES);advanceHost(now+2);assert(delayed.count==0);
 Card *a=make(@"a");cards=@[a];[requests removeAllObjects];offeredKey=0;
 claim(@"a",YES,(STHVRect){0});return a;
}
static void testDelayedHold(BOOL opening){
 delayedScenario=opening?"opening":"shorter";
 STHVRect tall={0,220,400,630};
 // Opening holds even a >60pt shrink; a later small shrink uses the other
 // one-second branch. Both MUST cause an actual geometry write when adopted.
 STHVRect shorter=opening?(STHVRect){0,340,400,510}:(STHVRect){0,260,400,590};
 Card *a=newDelayedScenario();sampleFrame(tall,NO);assert(viewportOwner==a);
 advanceHost(now+(opening?.05:.31));
 int before=writes;uint64_t generation=sbPhysicalGeneration;
 sampleFrame(shorter,NO);double heldAt=now;
 assert(writes==before&&sbPhysicalGeneration==generation&&STHVNear(physicalKeyboard,tall,0));
 advanceHost(heldAt+.999);
 assert(writes==before&&sbPhysicalGeneration==generation&&STHVNear(physicalKeyboard,tall,0));
 int calls=animationCalls;advanceHost(heldAt+1);
 assert(animationCalls==calls+1&&writes==before+1&&sbPhysicalGeneration==generation+1);
 assert(viewportOwner==a&&STHVNear(physicalKeyboard,shorter,0));
 assert(STHVNear(layouts[@"a"].card,STHVTarget(originalCard,testScreen,shorter),.001));
 advanceHost(now+.17);assert(writes==before+1); // The 160ms settle is idempotent too.

 // Two held reports: the first serial must do absolutely nothing at its own
 // deadline, then the latest one must commit once in its own transaction.
 a=newDelayedScenario();sampleFrame(tall,NO);advanceHost(now+(opening?.05:.31));
 sampleFrame(shorter,NO);double oldAt=now;NSUInteger oldSerial=shorterSerial;
 advanceHost(now+.05);
 STHVRect latest=opening?(STHVRect){0,300,400,550}:(STHVRect){0,250,400,600};
 sampleFrame(latest,NO);double latestAt=now;assert(shorterSerial!=oldSerial);
 before=writes;generation=sbPhysicalGeneration;
 advanceHost(oldAt+.999);calls=animationCalls;advanceHost(oldAt+1);
 assert(animationCalls==calls&&writes==before&&sbPhysicalGeneration==generation&&STHVNear(physicalKeyboard,tall,0));
 advanceHost(latestAt+.999);assert(writes==before&&sbPhysicalGeneration==generation);
 calls=animationCalls;advanceHost(latestAt+1);
 assert(animationCalls==calls+1&&writes==before+1&&sbPhysicalGeneration==generation+1);
 assert(viewportOwner==a&&STHVNear(physicalKeyboard,latest,0));
 assert(STHVNear(layouts[@"a"].card,STHVTarget(originalCard,testScreen,latest),.001));

 // A newer report that confirms the held tall frame is just as authoritative
 // as growth. Previously physical-same left the old shorter serial valid.
 a=newDelayedScenario();sampleFrame(tall,NO);advanceHost(now+(opening?.05:.31));
 sampleFrame(shorter,NO);double sameOldAt=now;NSUInteger sameOldSerial=shorterSerial;
 advanceHost(now+.05);sampleFrame(tall,NO);assert(shorterSerial!=sameOldSerial);
 before=writes;generation=sbPhysicalGeneration;
 advanceHost(sameOldAt+.999);calls=animationCalls;advanceHost(sameOldAt+1);
 assert(animationCalls==calls&&writes==before&&sbPhysicalGeneration==generation&&STHVNear(physicalKeyboard,tall,0));
 assert(viewportOwner==a&&STHVNear(layouts[@"a"].card,STHVTarget(originalCard,testScreen,tall),.001));

 // Growth cancels a held shrink, including its later callback. This is not a
 // timer-driven geometry update, and cannot nest the synchronous native ABI.
 a=newDelayedScenario();sampleFrame(tall,NO);advanceHost(now+(opening?.05:.31));
 sampleFrame(shorter,NO);advanceHost(now+.05);
 STHVRect taller={0,216,400,634};sampleFrame(taller,NO);
 before=writes;generation=sbPhysicalGeneration;advanceHost(now+2);
 assert(viewportOwner==a&&writes==before&&sbPhysicalGeneration==generation&&STHVNear(physicalKeyboard,taller,0));

 // Hide must restore once, invalidate BOTH shorter/settle work, and never be
 // revived by an old callback (or by the still-active application request).
 a=newDelayedScenario();sampleFrame(tall,NO);advanceHost(now+(opening?.05:.31));
 sampleFrame(shorter,NO);advanceHost(now+.05);before=writes;sample(YES);
 assert(!viewportOwner&&writes==before+1&&a.scale==originalGeometry[0]&&!sbKeyboardVisible);
 assert(a.offset.width==originalGeometry[1]&&a.offset.height==originalGeometry[2]);
 assert(STHVNear(vr(STHNativeRect((__bridge void *)a)),originalCard,.001));
 before=writes;generation=sbPhysicalGeneration;calls=animationCalls;advanceHost(now+2);
 assert(delayed.count==0&&animationCalls==calls&&writes==before&&sbPhysicalGeneration==generation);
 assert(!viewportOwner&&!layouts[@"a"].keyboardVisible);
}
int main(int argc,const char *argv[]){@autoreleasepool{
 delayed=[NSMutableArray new];requests=[NSMutableDictionary new];layouts=[NSMutableDictionary new];
 // Run the same production callback in isolation for baseline/mutation CI.
 if(argc==2){
  assert(!strcmp(argv[1],"--delayed-opening")||!strcmp(argv[1],"--delayed-shorter"));
  testDelayedHold(!strcmp(argv[1],"--delayed-opening"));
  assert(transaction==0&&maxTransactionDepth==1&&delayed.count==0);
  printf("Viewport host isolated delayed %s: passed\n",delayedScenario);return 0;
 }
 assert(argc==1);
 for(int cycle=0;cycle<200;cycle++){
  advanceHost(10+cycle*10);Card *a=make(@"a"),*b=make(@"b");cards=@[a,b];[requests removeAllObjects];offeredKey=0;sample(YES);registry();
  assert(awakeCount==2);
  assert(layouts[@"a"].hosted&&!layouts[@"a"].active&&!layouts[@"a"].keyboardVisible);
  int before=writes;claim(@"a",YES,realKeys);registry();assert(!viewportOwner&&writes==before); // App frame cannot create SB authority.
  claim(@"fullscreen",YES,realKeys);sample(NO);assert(!viewportOwner&&writes==before);
  claim(@"a",YES,(STHVRect){0,774,430,158});registry();assert(viewportOwner==a&&a.scale==1&&b.scale==.8);
  uint64_t generation=sbPhysicalGeneration;before=writes;
  for(int n=0;n<4;n++){claim(@"a",YES,(STHVRect){0,932+n,430,97});registry();assert(sbPhysicalGeneration==generation&&STHVNear(physicalKeyboard,realKeys,0)&&writes==before&&layouts[@"a"].keyboardVisible);}
  unavailable=YES;registry();unavailable=NO;registry();assert(viewportOwner==a&&writes==before);
  claim(@"b",YES,(STHVRect){0});registry();assert(viewportOwner==b&&a.scale==.8&&b.scale==1);
  claim(@"a",NO,(STHVRect){0});before=writes;registry();assert(viewportOwner==b&&writes==before);
  sample(YES);assert(!viewportOwner&&!layouts[@"b"].keyboardVisible&&!STHViewportKeyboardExcludes(CGPointMake(100,650)));
  before=writes;claim(@"b",YES,realKeys);registry();assert(!viewportOwner&&writes==before); // New app Will cannot undo an SB hide.
  sample(NO);assert(viewportOwner==b);b.scale=.93;b.offset=CGSizeMake(55,66);before=writes;registry();assert(writes==before&&STHVNear(layouts[@"b"].card,vr(STHNativeRect((__bridge void *)b)),.001));
  claim(@"b",NO,(STHVRect){0});registry();assert(!viewportOwner&&b.scale==.93&&b.offset.width==55);
  claim(@"a",YES,(STHVRect){0});registry();assert(viewportOwner==a);
  transaction=1;a.minimized=YES;STHViewportModelMinimized((__bridge void *)a);transaction=0;registry();assert(!viewportOwner&&!layouts[@"a"].hosted);a.minimized=NO;
  claim(@"b",YES,(STHVRect){0});registry();STHViewportSetLocalInput(YES);assert(!viewportOwner);registry();STHViewportSetLocalInput(NO);registry();assert(!viewportOwner);
  claim(@"b",YES,(STHVRect){0});registry();cards=@[a];registry();assert(!viewportOwner&&!layouts[@"b"].hosted);
  claim(@"a",YES,(STHVRect){0});registry();registryMissing=YES;claim(@"a",NO,(STHVRect){0});registry();assert(!viewportOwner);registryMissing=NO;
  claim(@"a",YES,(STHVRect){0});registry();oversized=YES;unavailable=YES;advanceHost(now+4);registry();assert(!viewportOwner);oversized=NO;unavailable=NO;
  enabled=NO;registry();assert(!layouts[@"a"].hosted);assert(awakeCount==0);enabled=YES;sample(YES);
 }
 testDelayedHold(YES);testDelayedHold(NO);
 // Exact uploaded device geometry. Only the declared SB sample is the oracle.
 testScreen=(STHVRect){0,0,430,932};realKeys=(STHVRect){0,590,430,342};Card *a=make(@"a");cards=@[a];[requests removeAllObjects];offeredKey=0;sample(YES);
 claim(@"a",YES,(STHVRect){0});sample(NO);assert(STHVNear(layouts[@"a"].card,(STHVRect){0,100.5,430,731},.001));
 int unchanged=writes;uint64_t gen=sbPhysicalGeneration;
 STHVRect raw[]={ {0,774,430,158},{0,804.6666666667,430,127.3333333333},{0,835.3333333333,430,96.6666666667},{0,932,430,97} };
 for(unsigned i=0;i<sizeof(raw)/sizeof(raw[0]);i++){
  claim(@"a",YES,raw[i]);registry();Packet *p=layouts[@"a"];STHVRect mapped;
  assert(STHVAuthoritativeMap(p.card,p.keyboard,testScreen,(STHVRect){0,0,430,731},p.physicalGeneration,p.keyboardVisible,&mapped));
  assert(fabs(mapped.y-489.5)<.001&&fabs(mapped.h-241.5)<.001&&p.physicalGeneration==gen&&writes==unchanged);
  assert(STHViewportKeyboardExcludes(CGPointMake(100,650)));
 }
 sample(YES);unchanged=writes;claim(@"a",YES,realKeys);registry();assert(writes==unchanged&&!viewportOwner);
 advanceHost(now+2);assert(delayed.count==0&&transaction==0&&maxTransactionDepth==1&&writes==unchanged);
 puts("Viewport32 host: 200 lifecycle cycles plus uploaded 430x932 fixture; app774/804.667/835.333/932 never replaces SB590; inset241.5 retained; opening/small-shrink holds commit at 1s in depth-one native transactions; superseded/growth/hide callbacks are inert; synchronous native entries never nest");
}return 0;}
