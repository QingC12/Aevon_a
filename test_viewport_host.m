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
@property BOOL active;
@property STHVRect card;
@property STHVRect keyboard;
@property uint64_t event;
@end
@implementation Packet @end
static NSArray<Card *> *cards;
static NSMutableDictionary<NSString *,Packet *> *requests,*layouts;
static uint64_t offeredKey,claimEvents;
static double timeValue;
static BOOL enabled=YES,unavailable,registryUnavailable,registryOversized;
static int writes,animations,transaction,releases,interruptions,refreshes,logs;
double STHVHostTestNow(void){return timeValue;}
BOOL STHSystemActionsEnabled(void){return enabled;}
BOOL STHSystemActionRuntimeReady(void){return YES;}
void *STHDockCopyFloating(void){return registryUnavailable?NULL:(__bridge void *)cards;}
size_t STHChooserManagersCount(void *p){return registryOversized?5000:[(__bridge NSArray *)p count];}
void *STHChooserCopyManagerAt(size_t i,void *p){return (__bridge void *)[(__bridge NSArray *)p objectAtIndex:i];}
void STHChooserReleaseArray(void *p){}
void STHChooserReleaseSwift(void *p){releases++;}
void *STHSystemCopyModelIdentifier(void *p){return (__bridge_retained void *)((__bridge Card *)p).bundle;}
BOOL STHNativeMinimized(void *p){return ((__bridge Card *)p).minimized;}
NSUInteger STHNativeOrientation(void *p){return 1;}
CGRect STHNativeRect(void *p){Card *c=(__bridge Card *)p;return CGRectMake(200+c.offset.width-200*c.scale,400+c.offset.height-312.5*c.scale,400*c.scale,625*c.scale);}
double STHNativeGetScale(void *p){return ((__bridge Card *)p).scale;}
CGSize STHNativeGetOffset(void *p){return ((__bridge Card *)p).offset;}
void STHNativeSetViewportGeometry(void *p,const double *g){assert(transaction==1);Card *c=(__bridge Card *)p;c.scale=g[0];c.offset=CGSizeMake(g[1],g[2]);writes++;}
void STHNativeRefreshGeometry(void *p){refreshes++;}
void STHCenterRunAnimation(void (^block)(void),int style){assert(style==0&&transaction==0);transaction=1;animations++;block();transaction=0;}
void STHGestureInputFocusChanged(void *p){interruptions++;}
uint64_t STHVKey(NSString *b){return [b isEqual:@"a"]?11:([b isEqual:@"b"]?22:33);}
uint64_t STHVRequestOwner(void){if(unavailable)return 0;for(NSString *b in requests)if(STHVKey(b)==offeredKey&&requests[b].active)return offeredKey;return 0;}
BOOL STHVReadRequest(NSString *b,STHVSnapshot *s){if(unavailable)return NO;Packet *p=requests[b];if(!p)return NO;if(s)*s=(STHVSnapshot){.active=p.active,.keyboard=p.keyboard,.owner=STHVKey(b),.event=p.event};return YES;}
BOOL STHVPublishLayout(NSString *b,BOOL active,STHVRect card,STHVRect keyboard){if(!b)return NO;Packet *p=[Packet new];p.active=active;p.card=card;p.keyboard=keyboard;layouts[b]=p;return YES;}
BOOL STHVReadProbe(NSString *b,STHVRect *a,STHVRect *p){return NO;}
NSDictionary *STHVRectJSON(STHVRect r){return @{@"x":@(r.x),@"y":@(r.y),@"w":@(r.w),@"h":@(r.h)};}
void STHVLog(NSString *event,NSString *b,NSDictionary *values){logs++;}
static Card *make(NSString *bundle){Card *c=[Card new];c.bundle=bundle;c.scale=.8;c.offset=CGSizeMake(0,20);return c;}
static void claim(NSString *bundle,BOOL active,STHVRect keyboard){Packet *p=[Packet new];p.active=active;p.event=++claimEvents;p.keyboard=keyboard;requests[bundle]=p;if(active)offeredKey=STHVKey(bundle);}
static void runRegistry(void){STHCenterRunAnimation(^{updateRegistry(YES);},0);}
static void physical(BOOL hide){STHCenterRunAnimation(^{STHViewportPhysicalWill(CGRectMake(0,550,400,300),hide);},0);}
int main(void){@autoreleasepool{
 requests=[NSMutableDictionary new];layouts=[NSMutableDictionary new];
 for(int i=0;i<200;i++){
  timeValue=10+i*10;Card *a=make(@"a"),*b=make(@"b");cards=@[a,b];[requests removeAllObjects];offeredKey=0;
  runRegistry();assert(!layouts[@"a"].active&&STHVValid(layouts[@"a"].card));
  // A fullscreen keyboard cannot resize either floating model without ownership.
  claim(@"fullscreen",YES,(STHVRect){0,550,400,300});int before=writes;physical(NO);assert(!viewportOwner&&writes==before);
  assert(STHViewportKeyboardExcludes(CGPointMake(100,600))&&!STHViewportKeyboardExcludes(CGPointMake(100,300)));
  claim(@"a",YES,(STHVRect){0,550,400,300});runRegistry();assert(viewportOwner==a&&a.scale==1&&layouts[@"a"].active);
  assert(b.scale==.8&&STHVNear(vr(STHNativeRect((__bridge void *)a)),layouts[@"a"].card,.001));
  before=writes;int prior=interruptions;physical(NO);runRegistry();assert(writes==before&&interruptions==prior);
  // An unreadable packet never causes a shrink/re-enlarge oscillation.
  unavailable=YES;runRegistry();unavailable=NO;runRegistry();assert(writes==before&&viewportOwner==a);
  // A definite end is immediate even though effective global owner is now zero.
  claim(@"a",NO,(STHVRect){0});physical(YES);assert(!viewportOwner&&fabs(a.scale-.8)<.001&&writes==before+1);
  assert(!STHViewportKeyboardExcludes(CGPointMake(100,600)));
  claim(@"a",YES,(STHVRect){0,550,400,300});runRegistry();assert(viewportOwner==a);
  claim(@"b",YES,(STHVRect){0,550,400,300});runRegistry();assert(viewportOwner==b&&a.scale==.8&&b.scale==1);
  // A late old-owner end and an unowned native hide cannot tear down B.
  claim(@"a",NO,(STHVRect){0});before=writes;physical(YES);assert(viewportOwner==b&&writes==before);
  claim(@"b",NO,(STHVRect){0});runRegistry();assert(!viewportOwner&&b.scale==.8);
  // Manual geometry is not overwritten by automatic restoration.
  claim(@"a",YES,(STHVRect){0,550,400,300});runRegistry();a.offset=CGSizeMake(55,66);a.scale=.93;
  before=writes;runRegistry();assert(writes==before&&STHVNear(layouts[@"a"].card,vr(STHNativeRect((__bridge void *)a)),.001));
  claim(@"a",NO,(STHVRect){0});runRegistry();assert(a.scale==.93&&a.offset.width==55&&a.offset.height==66);
  a.scale=.8;a.offset=CGSizeMake(0,20);claim(@"a",YES,(STHVRect){0,550,400,300});runRegistry();
  transaction=1;a.minimized=YES;STHViewportModelMinimized((__bridge void *)a);transaction=0;
  assert(!viewportOwner&&a.scale==.8);runRegistry();assert(!viewportOwner);a.minimized=NO;
  claim(@"b",YES,(STHVRect){0,550,400,300});runRegistry();STHViewportSetLocalInput(YES);assert(!viewportOwner&&b.scale==.8);
  runRegistry();assert(!viewportOwner);STHViewportSetLocalInput(NO);runRegistry();assert(!viewportOwner);
  claim(@"b",YES,(STHVRect){0,550,400,300});runRegistry();cards=@[a];runRegistry();assert(!viewportOwner&&b.scale==.8&&!STHVValid(layouts[@"b"].card));
  claim(@"a",YES,(STHVRect){0,550,400,300});runRegistry();unavailable=YES;timeValue+=4;runRegistry();unavailable=NO;assert(!viewportOwner);
  claim(@"a",YES,(STHVRect){0,550,400,300});runRegistry();registryUnavailable=YES;
  claim(@"a",NO,(STHVRect){0});runRegistry();assert(!viewportOwner&&a.scale==.8);registryUnavailable=NO;
  claim(@"a",YES,(STHVRect){0,550,400,300});runRegistry();registryOversized=YES;unavailable=YES;timeValue+=4;
  runRegistry();assert(!viewportOwner&&a.scale==.8);registryOversized=NO;unavailable=NO;
  enabled=NO;runRegistry();assert(!STHVValid(layouts[@"a"].card));enabled=YES;
 }
 assert(writes>200&&refreshes>writes&&releases>400);
 puts("Viewport host: 200 fullscreen/focus/native-Will/duplicate/unavailable/end/handoff/late-hide/manual-change/dock/local/removed/expiry/disable cycles; original single transaction; no native legacy avoidance call");
}return 0;}
