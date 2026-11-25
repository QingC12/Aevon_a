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
static dispatch_source_t watchTimer;
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
 cachedSceneBounds=scene;cacheEnabled=YES;
 cacheExpires=fmin(reflowNow()+ttl,hostedSceneAt+60.0);
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
  double deadline=fmin(reflowNow()+ttl,hostedSceneAt+60.0);
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
typedef NS_ENUM(NSUInteger,STHRSceneKind){
 STHRSceneTransientMissing,STHRSceneUnique,STHRSceneFullscreen,STHRSceneAmbiguous
};
typedef struct {STHRSceneKind kind;__unsafe_unretained UIWindowScene *scene;CGRect bounds;} STHRSceneChoice;
/* UIScreen.bounds is process-wide: even one fullscreen plus one card cannot
 * share a carded answer. Count all usable scenes on this display, including a
 * temporarily unreadable one; key loss/background transitions remain missing. */
static STHRSceneChoice chooseScene(UIScreen *display,CGRect physical){
 STHRSceneChoice choice={STHRSceneTransientMissing,nil,CGRectZero};
 UIWindowScene *only=nil;
 for(UIScene *candidate in UIApplication.sharedApplication.connectedScenes){
  if(!usableScene(candidate))continue;
  UIWindowScene *scene=(UIWindowScene *)candidate;
  if(scene.screen!=display)continue;
  // Count before reading any viewport. An unreadable first card must not hide
  // a second active consumer and accidentally preserve the old global answer.
  if(only)return (STHRSceneChoice){STHRSceneAmbiguous,nil,CGRectZero};
  only=scene;
 }
 if(!only||!finiteRect(physical))return choice;
 @try{
  CGRect bounds=only.coordinateSpace.bounds;
  if(finiteRect(bounds))choice=(STHRSceneChoice){STHRSceneDiffersFromPhysicalScreen(hrSize(bounds),hrSize(physical))?STHRSceneUnique:STHRSceneFullscreen,only,bounds};
 }@catch(NSException *exception){ /* A unique scene may be between spaces. */ }
 return choice;
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
static void ensureWatch(void){
 if(watchTimer||!started)return;
 watchTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
 if(!watchTimer)return;
 dispatch_source_set_timer(watchTimer,dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),200*NSEC_PER_MSEC,80*NSEC_PER_MSEC);
 dispatch_source_set_event_handler(watchTimer,^{
  if(!NSThread.isMainThread||refreshing)return;
  // A card is resized by the windowing feature, not by this process: a short
  // period is the only way to see the new viewport before the next host beat.
  refreshCache(@"scene-watch");
 });
 dispatch_resume(watchTimer);
}
static void stopWatch(void){
 if(!watchTimer)return;
 dispatch_source_cancel(watchTimer);watchTimer=nil;
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
  // Ambiguity is decisive even if the physical screen is temporarily unreadable.
  STHRSceneChoice choice=chooseScene(display,physical);
  UIWindowScene *scene=choice.scene;CGRect bounds=choice.bounds;
  if(choice.kind==STHRSceneAmbiguous){
   // Ambiguity is positive evidence against a process-wide carded answer, not
   // a transition. Forget it so host beats cannot renew or resurrect it.
   hasHostedScene=NO;cacheDisarm();ensureWatch();
   publishState(reason,NO,@"ambiguous",CGRectZero,physical,0);
   return;
  }
  // An unreadable physical screen alone proves nothing either way.
  if(!finiteRect(physical))return;
  cacheStorePhysical(physical);
  if(!ensureHook(display))return;
  STHRPolicyInput policy={.inject=true,.settingMaskPresent=true,.settingBit31=host.reflowEnabled,
   .queryIsMainScreen=true,.sceneIsOnMainScreen=scene&&scene.screen==display,.hostedLayout=host.hosted,
   .sceneConnected=scene!=nil,.sceneUsable=scene!=nil,
   .sceneBoundsValid=finiteRect(bounds),.physicalBoundsValid=finiteRect(physical),
   .sceneSize=hrSize(bounds),.physicalSize=hrSize(physical)};
  if(scene&&STHRShouldReflow(&policy)){
   hostedScene=bounds;hasHostedScene=YES;hostedSceneAt=reflowNow();
   cacheArm(bounds,3.0);ensureWatch();
   publishState(reason,YES,@"scene",bounds,physical,scene.activationState);
   return;
  }
  if(choice.kind==STHRSceneFullscreen){
   // The application is genuinely laid out on the whole screen right now: it
   // returns to the native answer instead of a remembered carded viewport.
   hasHostedScene=NO;stopWatch();cacheDisarm();
   publishState(reason,NO,@"native-full-screen",CGRectZero,physical,scene.activationState);
   return;
  }
  // Only transient absence may reuse a previously proven single viewport.
  // Host heartbeats are not scene evidence and must not extend this deadline.
  if(choice.kind==STHRSceneTransientMissing&&hasHostedScene&&reflowNow()-hostedSceneAt<60.0){
   cacheArm(hostedScene,fmin(2.0,60.0-(reflowNow()-hostedSceneAt)));ensureWatch();
   publishState(reason,YES,@"memory",hostedScene,physical,0);
   return;
  }
  cacheDisarm();
  publishState(reason,NO,@"unknown",CGRectZero,physical,0);
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
    if(hasHostedScene&&reflowNow()-hostedSceneAt<60.0)cacheRenew(3.0);
    ensureWatch();
   }
  }
  scheduleRefresh(@"host-layout");
 });
 scheduleRefresh(@"post-launch-install");
}
