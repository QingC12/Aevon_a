#define STH_VIEWPORT_HOST_TEST 1
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <assert.h>
#import "ViewportHost.m"
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
static int writes,transaction,interruptions,refreshes;
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
void STHNativeSetViewportGeometry(void *p,const double *g){assert(transaction==1);Card *c=(__bridge Card *)p;c.scale=g[0];c.offset=CGSizeMake(g[1],g[2]);writes++;}
void STHNativeRefreshGeometry(void *p){refreshes++;}
void STHCenterRunAnimation(void (^block)(void),int style){assert(style==0&&!transaction);transaction=1;block();transaction=0;}
void STHGestureInputFocusChanged(void *p){interruptions++;}
uint64_t STHVKey(NSString *b){return [b isEqual:@"a"]?11:([b isEqual:@"b"]?22:33);}
uint64_t STHVRequestOwner(void){if(unavailable)return 0;for(NSString *b in requests)if(STHVKey(b)==offeredKey&&requests[b].active)return offeredKey;return 0;}
BOOL STHVReadRequest(NSString *b,STHVSnapshot *s){Packet *p=requests[b];if(unavailable||!p)return NO;if(s)*s=(STHVSnapshot){.active=p.active,.keyboard=p.keyboard,.owner=STHVKey(b),.event=p.event};return YES;}
BOOL STHVPublishLayoutPolicyState(NSString *b,BOOL active,STHVRect card,STHVRect physical,uint64_t generation,BOOL visible,BOOL reflow){assert(!active||(visible&&generation));Packet *p=[Packet new];p.active=active;p.card=card;p.keyboard=physical;p.physicalGeneration=generation;p.keyboardVisible=visible;p.hosted=STHVValid(card);layouts[b]=p;return YES;}
BOOL STHVReadClientFrames(NSString *b,STHVSnapshot *out){return NO;}
BOOL STHVReadProbe(NSString *b,STHVRect *a,STHVRect *p){return NO;}
NSDictionary *STHVRectJSON(STHVRect r){return @{@"x":@(r.x),@"y":@(r.y),@"w":@(r.w),@"h":@(r.h)};}
void STHVLog(NSString *e,NSString *b,NSDictionary *v){}
static Card *make(NSString *b){Card *c=[Card new];c.bundle=b;c.scale=.8;return c;}
static void claim(NSString *b,BOOL active,STHVRect raw){Packet *p=[Packet new];p.active=active;p.keyboard=raw;p.event=++events;requests[b]=p;if(active)offeredKey=STHVKey(b);}
static void registry(void){STHCenterRunAnimation(^{updateRegistry(YES);},0);}
static void sample(BOOL hide){STHCenterRunAnimation(^{STHViewportPhysicalWill(cr(realKeys),hide);},0);}
int main(void){@autoreleasepool{
 requests=[NSMutableDictionary new];layouts=[NSMutableDictionary new];
 for(int cycle=0;cycle<200;cycle++){
  now=10+cycle*10;Card *a=make(@"a"),*b=make(@"b");cards=@[a,b];[requests removeAllObjects];offeredKey=0;sample(YES);registry();
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
  claim(@"a",YES,(STHVRect){0});registry();oversized=YES;unavailable=YES;now+=4;registry();assert(!viewportOwner);oversized=NO;unavailable=NO;
  enabled=NO;registry();assert(!layouts[@"a"].hosted);assert(awakeCount==0);enabled=YES;sample(YES);
 }
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
 puts("Viewport32 host: 200 lifecycle cycles plus uploaded 430x932 fixture; app774/804.667/835.333/932 never replaces SB590; inset241.5 retained; hide cannot be revived by app claims; native transactions and hosted baselines preserved");
}return 0;}
