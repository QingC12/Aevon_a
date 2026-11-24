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
 host.hosted=NO;changed();prohibitUIKit=YES;assert(!cacheEnabled);
 assert(nativeBounds&&!refreshing&&!readingNative);
 puts("Reflow33 production runtime: 200 launch/fullscreen/hosted/expiry/native-IMP-reentry cycles; 40000 bounds reads with zero UIKit traversal; key loss keeps the carded viewport; extensions/no-host do not hook or query application; no defaults or private scene update interception");
#endif
}return 0;}
