// Hosted app compatibility. Never inspect UIKit scene state from a bounds getter.
#import "AppSceneReflow.h"
#import "AppSceneReflowPolicy.h"
#import "ViewportProcess.h"
#import "ViewportDiagnostics.h"
#import "ViewportBus.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <os/lock.h>
#include <string.h>

/* UIKit declares this on UIView. It is repeated here because the stand-in
 * UIWindow used by the deterministic test runner is deliberately minimal, while
 * the reflow runtime only ever sends this one layout request to a window. */
@interface UIWindow (STHSceneReflowLayout)
-(void)setNeedsLayout;
@end

/* The cached answer is read from every thread an application asks UIScreen from,
 * so it lives behind an unfair lock and is copied out in one shot. The getter
 * never calls UIKit, logs, allocates or posts while holding it. */
static CGRect (*nativeBounds)(id,SEL);
static UIScreen *primaryDisplay;
static os_unfair_lock cacheLock=OS_UNFAIR_LOCK_INIT;
static CGRect cachedSceneBounds,cachedPhysicalBounds;
static double cacheExpires;
static BOOL cacheEnabled;
static BOOL started,hookInstalled,refreshing,refreshQueued;
static __thread BOOL readingNative;
static NSString *processBundle,*lastState;
static CGRect hostedScene;
static BOOL hasHostedScene;
static double hostedSceneAt;
static double lastHostAt;
static double reflowNow(void){
#if defined(STH_SCENE_REFLOW_TEST)
 extern double STHVReflowTestNow(void);return STHVReflowTestNow();
#else
 return CACurrentMediaTime();
#endif
}
static BOOL finiteRect(CGRect r){return isfinite(r.origin.x)&&isfinite(r.origin.y)&&isfinite(r.size.width)&&isfinite(r.size.height)&&r.size.width>0&&r.size.height>0;}
static STHRSize hrSize(CGRect r){return (STHRSize){r.size.width,r.size.height};}
static STHVRect vr(CGRect r){return (STHVRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
typedef struct {BOOL armed;CGRect scene;} STHCacheView;
static STHCacheView cacheView(void){
 STHCacheView view={NO,CGRectZero};
 os_unfair_lock_lock(&cacheLock);
 view.scene=cachedSceneBounds;
 view.armed=cacheEnabled&&reflowNow()<=cacheExpires;
 os_unfair_lock_unlock(&cacheLock);
 return view;
}
static CGRect cachePhysicalValue(void){
 os_unfair_lock_lock(&cacheLock);CGRect value=cachedPhysicalBounds;os_unfair_lock_unlock(&cacheLock);
 return value;
}
static void cacheArm(CGRect scene,double ttl){
 os_unfair_lock_lock(&cacheLock);
 cachedSceneBounds=scene;cacheEnabled=YES;cacheExpires=reflowNow()+ttl;
 os_unfair_lock_unlock(&cacheLock);
}
/* Extend an existing answer without replacing it: the host republishes every
 * second, so a carded application never falls back to the physical screen
 * between two refreshes. */
static void cacheRenew(double ttl){
 os_unfair_lock_lock(&cacheLock);
 // An answer that already lapsed is not resurrected: only a fresh scene read
 // may put a carded viewport back in front of the application.
 if(cacheEnabled&&reflowNow()<=cacheExpires){
  double deadline=reflowNow()+ttl;
  if(deadline>cacheExpires)cacheExpires=deadline;
 }
 os_unfair_lock_unlock(&cacheLock);
}
static void cacheDisarm(void){
 os_unfair_lock_lock(&cacheLock);cacheEnabled=NO;os_unfair_lock_unlock(&cacheLock);
}
static void cacheStorePhysical(CGRect physical){
 os_unfair_lock_lock(&cacheLock);cachedPhysicalBounds=physical;os_unfair_lock_unlock(&cacheLock);
}
CGRect STHVUnmodifiedScreenBounds(UIScreen *screen){
 if(!screen)return CGRectZero;
 if(!nativeBounds)return screen.bounds;
 // A previously installed implementation may query UIScreen again. Stop the
 // chain at the last unmodified result, without asking UIApplication for state.
 if(readingNative)return screen==primaryDisplay?cachePhysicalValue():CGRectZero;
 readingNative=YES;
 @try{return nativeBounds(screen,@selector(bounds));}
 @finally{readingNative=NO;}
}
static CGRect screenBounds(id screen,SEL selector){
 // Deliberately no mainScreen, connectedScenes, window, preferences, IPC,
 // notification or logging call here. UIKit may already hold a scene lock.
 if(readingNative)return screen==primaryDisplay?cachePhysicalValue():CGRectZero;
 STHCacheView view=cacheView();
 // Applications read this from work queues as well as the main thread: the
 // layout size cannot depend on which thread happened to ask.
 if(view.armed&&screen==primaryDisplay&&finiteRect(view.scene))return view.scene;
 return STHVUnmodifiedScreenBounds(screen);
}
static void publishState(NSString *reason,BOOL enabled,NSString *source,CGRect scene,CGRect physical,NSUInteger activation){
 // This runs on every reflow refresh, so the switch is checked before the state
 // string is formatted rather than inside the recorder.
 if(!STHVDiagnosticsEnabled())return;
 NSString *state=[NSString stringWithFormat:@"%d|%@|%.2f/%.2f/%.2f/%.2f|%lu",enabled,source?:@"-",
  scene.size.width,scene.size.height,physical.size.width,physical.size.height,(unsigned long)activation];
 if([state isEqual:lastState])return;lastState=state;
 STHVLog(@"reflow-state",processBundle,@{@"reason":reason?:@"refresh",@"source":source?:@"-",@"enabled":@(enabled),@"execution":@"post-launch-hosted-cache",@"activation":@(activation),@"scene":STHVRectJSON(vr(scene)),@"unmodifiedScreen":STHVRectJSON(vr(physical))});
}
static BOOL usableScene(UIScene *scene){
 if(![scene isKindOfClass:UIWindowScene.class])return NO;
 UISceneActivationState state=scene.activationState;
 return state!=UISceneActivationStateBackground&&state!=UISceneActivationStateUnattached;
}
/* A carded scene is the one whose viewport is not the physical screen. When two
 * scenes claim that shape the answer is ambiguous and this path stays native;
 * a lone full-screen scene is a real answer, not a missing one. */
static UIWindowScene *cardedScene(UIScreen *display,CGRect physical,BOOL *sawFullScreen){
 UIWindowScene *found=nil,*plain=nil;NSUInteger matches=0;
 for(UIScene *candidate in UIApplication.sharedApplication.connectedScenes){
  if(!usableScene(candidate))continue;
  UIWindowScene *scene=(UIWindowScene *)candidate;
  if(scene.screen!=display)continue;
  CGRect bounds=scene.coordinateSpace.bounds;
  if(!finiteRect(bounds))continue;
  if(STHRSceneDiffersFromPhysicalScreen(hrSize(bounds),hrSize(physical))){matches++;found=scene;}
  else plain=scene;
 }
 if(sawFullScreen)*sawFullScreen=(matches==0&&plain!=nil);
 return matches==1?found:nil;
}
static BOOL ensureHook(UIScreen *display){
 if(hookInstalled)return YES;
 Method method=class_getInstanceMethod(UIScreen.class,@selector(bounds));char type[80]={0};
 if(!method||method_getNumberOfArguments(method)!=2)return NO;
 method_getReturnType(method,type,sizeof(type));if(strcmp(type,@encode(CGRect)))return NO;
 IMP previous=method_getImplementation(method);if(previous==(IMP)screenBounds)return NO;
 primaryDisplay=display;nativeBounds=(void *)previous;method_setImplementation(method,(IMP)screenBounds);
 hookInstalled=YES;
 return YES;
}
static void stopWatch(void);
static void refreshCache(NSString *reason);
static CFRunLoopObserverRef watchObserver;
static double lastWatchAt;
static void ensureWatch(void){
 if(watchObserver||!started)return;
 // A card is resized by the windowing feature, not by this process, so the new
 // viewport has to be observed rather than announced. A run loop observer is
 // used instead of a timer because a resize is followed by a layout pass in the
 // same cycle: the answer is refreshed at the next safe point of the main run
 // loop, not up to a timer interval later, and an idle application spends
 // nothing. The throttle keeps a full scene read off every single turn.
 watchObserver=CFRunLoopObserverCreateWithHandler(NULL,kCFRunLoopBeforeWaiting|kCFRunLoopAfterWaiting,true,0,^(CFRunLoopObserverRef observer,CFRunLoopActivity activity){
  (void)observer;(void)activity;
  if(!NSThread.isMainThread||refreshing)return;
  if(reflowNow()-lastWatchAt<0.10)return;
  lastWatchAt=reflowNow();
  refreshCache(@"scene-watch");
 });
 if(!watchObserver)return;
 CFRunLoopAddObserver(CFRunLoopGetMain(),watchObserver,kCFRunLoopCommonModes);
}
static void stopWatch(void){
 if(!watchObserver)return;
 CFRunLoopRemoveObserver(CFRunLoopGetMain(),watchObserver,kCFRunLoopCommonModes);
 CFRelease(watchObserver);watchObserver=NULL;
}
/* A size the application has not seen before is a new layout question. Marking
 * the windows dirty costs one pass and makes an application that reads the
 * screen size while laying out ask again, instead of keeping the previous ratio
 * on screen until something unrelated schedules a pass. It is only sent when the
 * answer really changed, and it never forces a layout from inside this cycle. */
static void nudgeLayout(void){
 @try{
  for(UIScene *candidate in UIApplication.sharedApplication.connectedScenes){
   if(![candidate isKindOfClass:UIWindowScene.class])continue;
   UIWindowScene *scene=(UIWindowScene *)candidate;
   if(scene.screen!=UIScreen.mainScreen)continue;
   for(UIWindow *window in scene.windows){
    if([NSStringFromClass(window.class) containsString:@"Keyboard"])continue;
    if([window respondsToSelector:@selector(setNeedsLayout)])[window setNeedsLayout];
   }
  }
 }@catch(NSException *exception){}
}
static BOOL answeredOnce;
static STHRSize answeredSize;
static void noteAnswer(CGRect answer){
 if(answeredOnce&&fabs(answer.size.width-answeredSize.width)<0.01&&fabs(answer.size.height-answeredSize.height)<0.01)return;
 answeredOnce=YES;answeredSize=(STHRSize){answer.size.width,answer.size.height};
 nudgeLayout();
}
static void refreshCache(NSString *reason){
 if(!started||!NSThread.isMainThread||refreshing)return;
 refreshing=YES;
 @try{
  STHVSnapshot host={0};
  BOOL known=STHVReadLayout(processBundle,&host);
  // Check authority BEFORE touching UIApplication/UIScreen. Normal full-screen
  // apps, widgets and unhosted startup need no scene traversal or screen hook.
  if(known&&(!host.hosted||!host.reflowEnabled||!STHVValid(host.card))){
   hasHostedScene=NO;lastHostAt=reflowNow();stopWatch();cacheDisarm();
   publishState(reason,NO,@"host-native",CGRectZero,CGRectZero,0);
   return;
  }
  if(!known){if(reflowNow()-lastHostAt>10.0){stopWatch();cacheDisarm();}return;}
  lastHostAt=reflowNow();
  UIScreen *display=UIScreen.mainScreen;
  CGRect physical=STHVUnmodifiedScreenBounds(display);
  // An unreadable physical screen proves nothing either way; keep the answer.
  if(!finiteRect(physical))return;
  cacheStorePhysical(physical);
  if(!ensureHook(display))return;
  // The card is the viewport. It is published in screen points on every change
  // and the scene is in those same points, so it describes the size a custom
  // window ratio produces even when the scene has not caught up yet - which is
  // the case that used to leave an application laid out for the previous width
  // while the card was already narrower.
  STHRSize card={host.card.w,host.card.h},viewport={0};
  if(STHRCardViewport(card,hrSize(physical),&viewport)){
   CGRect bounds=CGRectMake(0,0,viewport.width,viewport.height);
   hostedScene=bounds;hasHostedScene=YES;hostedSceneAt=reflowNow();
   cacheArm(bounds,3.0);ensureWatch();noteAnswer(bounds);
   publishState(reason,YES,@"card",bounds,physical,0);
   return;
  }
  BOOL fullScreen=NO;UIWindowScene *scene=cardedScene(display,physical,&fullScreen);
  CGRect bounds=scene?scene.coordinateSpace.bounds:CGRectZero;
  STHRPolicyInput policy={.inject=true,.settingMaskPresent=true,.settingBit31=host.reflowEnabled,
   .queryIsMainScreen=true,.sceneIsOnMainScreen=scene&&scene.screen==display,.hostedLayout=host.hosted,
   .sceneConnected=scene!=nil,.sceneUsable=scene!=nil,
   .sceneBoundsValid=finiteRect(bounds),.physicalBoundsValid=finiteRect(physical),
   .sceneSize=hrSize(bounds),.physicalSize=hrSize(physical)};
  if(scene&&STHRShouldReflow(&policy)){
   hostedScene=bounds;hasHostedScene=YES;hostedSceneAt=reflowNow();
   cacheArm(bounds,3.0);ensureWatch();noteAnswer(bounds);
   publishState(reason,YES,@"scene",bounds,physical,scene.activationState);
   return;
  }
  if(fullScreen){
   // The application is genuinely laid out on the whole screen right now: it
   // returns to the native answer instead of a remembered carded viewport.
   stopWatch();cacheDisarm();
   publishState(reason,NO,@"native-full-screen",CGRectZero,physical,scene.activationState);
   return;
  }
  // No readable carded scene yet (resize in flight, transition, ambiguous). A
  // viewport this process already proved carded is the only honest answer
  // while the host still reports the card, so the layout does not fall back to
  // the full screen and stay there.
  if(hasHostedScene&&reflowNow()-hostedSceneAt<60.0){
   cacheArm(hostedScene,2.0);ensureWatch();noteAnswer(hostedScene);
   publishState(reason,YES,@"memory",hostedScene,physical,scene.activationState);
   return;
  }
  publishState(reason,NO,@"unknown",CGRectZero,physical,scene.activationState);
 }@catch(NSException *exception){cacheDisarm();}
 @finally{refreshing=NO;}
}
static void scheduleRefresh(NSString *reason){
 if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{scheduleRefresh(reason);});return;}
 if(!started||refreshQueued)return;refreshQueued=YES;
 // Defer out of lifecycle/layout notification delivery and any UIKit locks.
 dispatch_async(dispatch_get_main_queue(),^{refreshQueued=NO;refreshCache(reason);});
}
void STHVInstallAppSceneReflow(void){
 if(!NSThread.isMainThread||started||!STHVApplicationBundleAllowed(NSBundle.mainBundle))return;
 // Called only by the client's observed post-launch activation, never dyld.
 started=YES;processBundle=[NSBundle.mainBundle.bundleIdentifier copy];lastHostAt=reflowNow();
 NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
 // Key window and activation transitions are refreshes, never a reason to drop
 // the answer: a card resizes and animates through exactly those states.
 for(NSString *name in @[UIApplicationDidBecomeActiveNotification,UISceneDidActivateNotification,UISceneWillDeactivateNotification,UISceneDidDisconnectNotification,UIWindowDidBecomeKeyNotification,UIWindowDidResignKeyNotification]){
  [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note){scheduleRefresh(note.name);}];
 }
 STHVObserveLayout(processBundle,^{
  if(!NSThread.isMainThread)return;
  STHVSnapshot host={0};
  if(STHVReadLayout(processBundle,&host)){
   lastHostAt=reflowNow();
   if(!host.hosted||!host.reflowEnabled||!STHVValid(host.card)){
    hasHostedScene=NO;stopWatch();cacheDisarm();
   }else{
    cacheRenew(3.0);ensureWatch();
   }
  }
  scheduleRefresh(@"host-layout");
 });
 scheduleRefresh(@"post-launch-install");
}
