#define STH_SCENE_REFLOW_TEST 1
#import "test_viewport_client_support.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <assert.h>
#import <stdio.h>
static NSMutableArray *jobs;
static void controlledAsync(dispatch_queue_t q,dispatch_block_t work){assert(q==dispatch_get_main_queue());if(!jobs)jobs=[NSMutableArray new];[jobs addObject:[work copy]];}
#define dispatch_async controlledAsync
#ifndef STH_REFLOW_SOURCE
#define STH_REFLOW_SOURCE "AppSceneReflow.m"
#endif
#import STH_REFLOW_SOURCE
#undef dispatch_async
static UIScreen *display;
static UIApplication *application;
static BOOL prohibitUIKit=YES,chainReentry;
static NSUInteger appQueries,screenQueries,sceneQueries;
static double clockValue=10;
static STHVSnapshot host;
static dispatch_block_t hostObserver;
double STHVReflowTestNow(void){return clockValue;}
@interface TestBundle:NSBundle
@property(copy) NSString *pathValue;
@property(strong) NSDictionary *metadata;
@end
@implementation TestBundle
-(NSString *)bundlePath{return self.pathValue;}
-(NSString *)bundleIdentifier{return @"test.stheno.viewport33.main";}
-(NSDictionary *)infoDictionary{return self.metadata;}
@end
static TestBundle *mainBundle;
static id bundleReplacement(id self,SEL selector){return mainBundle;}
@implementation TestSpace
-(CGRect)convertRect:(CGRect)r toCoordinateSpace:(id)space{return r;}
@end
@interface UnreadableSpace:TestSpace @end
@implementation UnreadableSpace
-(CGRect)bounds{ @throw [NSException exceptionWithName:@"TransientSpace" reason:@"scene changing spaces" userInfo:nil]; }
@end
@implementation UIScreen
+(UIScreen *)mainScreen{screenQueries++;assert(!prohibitUIKit);return display;}
-(CGRect)bounds{if(chainReentry){chainReentry=NO;return self.bounds;}return _bounds;}
@end
@implementation UIScene @end
@implementation UIWindowScene @end
@implementation UIView
-(CGRect)convertRect:(CGRect)r toCoordinateSpace:(id)space{return r;}
@end
@implementation UIWindow @end
@implementation UIApplication
+(UIApplication *)sharedApplication{appQueries++;assert(!prohibitUIKit);return application;}
-(NSSet *)connectedScenes{sceneQueries++;assert(!prohibitUIKit);return _connectedScenes;}
@end
BOOL STHVReadLayout(NSString *bundle,STHVSnapshot *out){if(out)*out=host;return YES;}
BOOL STHVSceneIsHosted(void){return host.hosted;}
BOOL STHVSceneReflowPolicy(BOOL *out){if(out)*out=host.reflowEnabled;return host.hosted;}
void STHVObserveLayout(NSString *b,dispatch_block_t block){hostObserver=[block copy];}
void STHVLog(NSString *e,NSString *b,NSDictionary *v){}
NSDictionary *STHVRectJSON(STHVRect r){return @{};}
static void drain(void){NSArray *batch=[jobs copy];[jobs removeAllObjects];for(dispatch_block_t block in batch)block();assert(!jobs.count);}
static void changed(void){assert(hostObserver);hostObserver();drain();}
static void expectHeight(CGFloat height){
 BOOL saved=prohibitUIKit;NSUInteger queries=appQueries+screenQueries+sceneQueries;
 prohibitUIKit=YES;assert(display.bounds.size.height==height);
 assert(appQueries+screenQueries+sceneQueries==queries);prohibitUIKit=saved;
}
int main(void){@autoreleasepool{
 mainBundle=[TestBundle new];mainBundle.pathValue=@"/Applications/Target.app";mainBundle.metadata=@{@"CFBundlePackageType":@"APPL"};
 method_setImplementation(class_getClassMethod(NSBundle.class,@selector(mainBundle)),(IMP)bundleReplacement);
 display=[UIScreen new];display.bounds=CGRectMake(0,0,430,932);display.coordinateSpace=[TestSpace new];display.coordinateSpace.bounds=display.bounds;display.fixedCoordinateSpace=display.coordinateSpace;
 application=[UIApplication new];UIWindowScene *scene=[UIWindowScene new];scene.activationState=UISceneActivationStateForegroundActive;scene.screen=display;scene.interfaceOrientation=UIInterfaceOrientationPortrait;scene.coordinateSpace=[TestSpace new];scene.coordinateSpace.bounds=CGRectMake(0,0,430,731);
 UIWindow *window=[UIWindow new];window.isKeyWindow=YES;scene.windows=@[window];application.connectedScenes=[NSSet setWithObject:scene];
 IMP original=method_getImplementation(class_getInstanceMethod(UIScreen.class,@selector(bounds)));
 host=(STHVSnapshot){0};
#if !defined(STH_REFLOW32_NEGATIVE)
 // A widget/extension must not install observers, access UIKit or hook bounds.
 mainBundle.pathValue=@"/Applications/Target.app/PlugIns/Widget.appex";mainBundle.metadata=@{@"CFBundlePackageType":@"XPC!",@"NSExtension":@{}};
 STHVInstallAppSceneReflow();assert(!started&&!hookInstalled&&!jobs.count&&appQueries==0&&screenQueries==0);
 mainBundle.pathValue=@"/Applications/Target.app";mainBundle.metadata=@{@"CFBundlePackageType":@"APPL"};
#endif
 // Old 32 enters UIApplication synchronously here, before any hosted decision.
 STHVInstallAppSceneReflow();drain();
 assert(appQueries==0&&screenQueries==0&&method_getImplementation(class_getInstanceMethod(UIScreen.class,@selector(bounds)))==original);
#if !defined(STH_REFLOW32_NEGATIVE)
 for(int i=0;i<200;i++){
  prohibitUIKit=NO;host.hosted=YES;host.reflowEnabled=YES;host.card=(STHVRect){43,173.6,344,584.8};
  changed();assert(hookInstalled&&cacheEnabled);
  NSUInteger queries=appQueries+screenQueries+sceneQueries;prohibitUIKit=YES;
  for(int j=0;j<200;j++){CGRect value=display.bounds;assert(value.size.width==430&&value.size.height==731);}
  assert(appQueries+screenQueries+sceneQueries==queries); // Getter is pure cached data.
  CGRect physical=STHVUnmodifiedScreenBounds(display);assert(physical.size.height==932);
  chainReentry=YES;physical=STHVUnmodifiedScreenBounds(display);assert(physical.size.height==932); // Guard before calling saved IMP.
  host.hosted=NO;changed();assert(!cacheEnabled);assert(display.bounds.size.height==932);
  assert(appQueries+screenQueries+sceneQueries==queries);
  // Full-screen/layout absent cannot be forced through a stale hosted cache.
  prohibitUIKit=NO;host.hosted=YES;scene.coordinateSpace.bounds=CGRectMake(0,0,430,932);changed();prohibitUIKit=YES;
  assert(!cacheEnabled&&display.bounds.size.height==932);scene.coordinateSpace.bounds=CGRectMake(0,0,430,731);
  prohibitUIKit=NO;changed();assert(cacheEnabled);prohibitUIKit=YES;
  clockValue+=3.1;assert(display.bounds.size.height==932);
  // NSUserDefaults change must neither recurse into policy nor schedule work.
  [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];assert(!jobs.count);
  host.hosted=NO;changed();
 }
 // A card that resigns the key window is still carded. Losing key is part of
 // every card resize and of every background card that keeps playing, so it
 // may not put the layout back on the physical screen.
 prohibitUIKit=NO;host.hosted=YES;host.reflowEnabled=YES;host.card=(STHVRect){43,173.6,344,584.8};
 scene.coordinateSpace.bounds=CGRectMake(0,0,430,731);changed();assert(cacheEnabled);
 [NSNotificationCenter.defaultCenter postNotificationName:UIWindowDidResignKeyNotification object:window];drain();
 assert(cacheEnabled);assert(display.bounds.size.height==731);
 // Foreground-inactive and background/keyless transitions retain the one
 // proven viewport; a host beat alone is not proof that memory stays current.
 window.isKeyWindow=NO;scene.activationState=UISceneActivationStateForegroundInactive;
 changed();expectHeight(731);
 scene.activationState=UISceneActivationStateBackground;changed();expectHeight(731);
 clockValue+=20;changed();expectHeight(731);
 scene.activationState=UISceneActivationStateForegroundActive;changed();expectHeight(731);
 application.connectedScenes=[NSSet set];changed();expectHeight(731);
 clockValue+=59.5;changed();expectHeight(731);
 assert(cacheExpires<=hostedSceneAt+60.0);
 clockValue+=0.2;hostObserver();assert(cacheExpires<=hostedSceneAt+60.0);drain();
 clockValue+=0.4;hostObserver();expectHeight(932); // Even before deferred refresh.
 drain();assert(!cacheEnabled);expectHeight(932);
 application.connectedScenes=[NSSet setWithObject:scene];changed();expectHeight(731);
 UIWindowScene *second=[UIWindowScene new];second.screen=display;
 second.activationState=UISceneActivationStateForegroundActive;
 second.coordinateSpace=[TestSpace new];second.windows=@[];
 for(int mode=0;mode<2;mode++){
  // A fullscreen sibling is just as ambiguous as a second, different card.
  second.coordinateSpace.bounds=CGRectMake(0,0,430,mode?612:932);
  assert(hasHostedScene&&cacheEnabled);
  application.connectedScenes=[NSSet setWithObjects:scene,second,nil];changed();
  assert(chooseScene(display,display.coordinateSpace.bounds).kind==STHRSceneAmbiguous);
  assert(!cacheEnabled&&!hasHostedScene);expectHeight(932);
  for(int beat=0;beat<75;beat++){
   clockValue+=1;hostObserver();
   assert(!cacheEnabled&&!hasHostedScene);expectHeight(932);
   drain();assert(!cacheEnabled&&!hasHostedScene);expectHeight(932);
  }
  // Neither absence nor host renewal can resurrect a pre-ambiguity viewport.
  application.connectedScenes=[NSSet set];changed();expectHeight(932);
  assert(!hasHostedScene);
  application.connectedScenes=[NSSet setWithObject:scene];changed();
  assert(cacheEnabled&&hasHostedScene);expectHeight(731);
 }
 // A unique scene's unreadable bounds are transient, not evidence of another
 // consumer. Invalid, nil and throwing spaces keep the proven card briefly.
 TestSpace *readable=scene.coordinateSpace;
 for(int unreadable=0;unreadable<4;unreadable++){
  if(unreadable==0)readable.bounds=CGRectZero;
  if(unreadable==1)readable.bounds=CGRectMake(0,0,NAN,731);
  if(unreadable==2)scene.coordinateSpace=nil;
  if(unreadable==3)scene.coordinateSpace=[UnreadableSpace new];
  changed();assert(hasHostedScene&&cacheEnabled);expectHeight(731);
  assert(chooseScene(display,display.coordinateSpace.bounds).kind==STHRSceneTransientMissing);
 }
 // Count all consumers before reading either space, irrespective of NSSet order.
 second.coordinateSpace=[UnreadableSpace new];
 application.connectedScenes=[NSSet setWithObjects:scene,second,nil];changed();
 assert(!hasHostedScene&&!cacheEnabled);expectHeight(932);
 scene.coordinateSpace=readable;readable.bounds=CGRectMake(0,0,430,731);
 second.coordinateSpace=[TestSpace new];second.coordinateSpace.bounds=CGRectMake(0,0,430,612);
 application.connectedScenes=[NSSet setWithObject:scene];changed();expectHeight(731);
 // Even unreadable physical bounds cannot hide an independently proven ambiguity.
 display.bounds=CGRectZero;
 application.connectedScenes=[NSSet setWithObjects:scene,second,nil];changed();
 assert(!cacheEnabled&&!hasHostedScene&&CGRectIsEmpty(display.bounds));
 display.bounds=CGRectMake(0,0,430,932);
 application.connectedScenes=[NSSet set];changed();expectHeight(932);
 application.connectedScenes=[NSSet setWithObject:scene];changed();expectHeight(731);
 // Same process, other screen is not an ambiguous main-screen consumer.
 UIScreen *external=[UIScreen new];second.screen=external;
 application.connectedScenes=[NSSet setWithObjects:scene,second,nil];changed();expectHeight(731);
 // Background siblings must not break the existing background-card lifecycle.
 second.screen=display;second.activationState=UISceneActivationStateBackground;
 changed();expectHeight(731);
 // Explicit fullscreen stays native and a fresh unique card can re-enter.
 application.connectedScenes=[NSSet setWithObject:scene];
 scene.coordinateSpace.bounds=display.coordinateSpace.bounds;changed();
 assert(chooseScene(display,display.coordinateSpace.bounds).kind==STHRSceneFullscreen);
 assert(!cacheEnabled&&!hasHostedScene);expectHeight(932);
 application.connectedScenes=[NSSet set];changed();expectHeight(932);
 application.connectedScenes=[NSSet setWithObject:scene];
 scene.coordinateSpace.bounds=CGRectMake(0,0,430,707);changed();expectHeight(707);
 chainReentry=YES;assert(STHVUnmodifiedScreenBounds(display).size.height==932);
 host.hosted=NO;changed();prohibitUIKit=YES;assert(!cacheEnabled);
 assert(nativeBounds&&!refreshing&&!readingNative);
 puts("Reflow production runtime: 200 launch/fullscreen/hosted/expiry/native-IMP-reentry cycles; 40000 pure bounds reads; keyloss/inactive/background/transient memory; absolute 60s expiry; mixed fullscreen+card and different-card ambiguity across 75 host beats each; no stale resurrection; single-scene recovery; external-screen isolation");
#endif
}return 0;}
