// Hosted app compatibility. Never inspect UIKit scene state from a bounds getter.
#import "AppSceneReflow.h"
#import "AppSceneReflowPolicy.h"
#import "ViewportProcess.h"
#import "ViewportDiagnostics.h"
#import "ViewportBus.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <string.h>
static CGRect (*nativeBounds)(id,SEL);
static UIScreen *primaryDisplay;
static CGRect cachedSceneBounds,cachedPhysicalBounds;
static double cacheExpires;
static BOOL started,hookInstalled,cacheEnabled,refreshing,refreshQueued;
static __thread BOOL readingNative;
static NSString *processBundle,*lastState;
static double reflowNow(void){
#if defined(STH_SCENE_REFLOW_TEST)
 extern double STHVReflowTestNow(void);return STHVReflowTestNow();
#else
 return CACurrentMediaTime();
#endif
}
static BOOL finiteRect(CGRect r){return isfinite(r.origin.x)&&isfinite(r.origin.y)&&isfinite(r.size.width)&&isfinite(r.size.height)&&r.size.width>0&&r.size.height>0;}
CGRect STHVUnmodifiedScreenBounds(UIScreen *screen){
 if(!screen)return CGRectZero;
 if(!nativeBounds)return screen.bounds;
 // A previously installed implementation may query UIScreen again. Stop the
 // chain at the last unmodified result, without asking UIApplication for state.
 if(readingNative)return screen==primaryDisplay?cachedPhysicalBounds:CGRectZero;
 readingNative=YES;
 @try{return nativeBounds(screen,@selector(bounds));}
 @finally{readingNative=NO;}
}
static CGRect screenBounds(id screen,SEL selector){
 // Deliberately no mainScreen, connectedScenes, window, preferences, IPC,
 // notification or logging call here. UIKit may already hold a scene lock.
 CGRect original=STHVUnmodifiedScreenBounds(screen);
 if(!NSThread.isMainThread||screen!=primaryDisplay||!cacheEnabled||reflowNow()>cacheExpires)return original;
 return cachedSceneBounds;
}
static void publishState(NSString *reason,BOOL enabled){
 NSString *state=[NSString stringWithFormat:@"%d/%.2f/%.2f/%.2f/%.2f",enabled,cachedSceneBounds.size.width,cachedSceneBounds.size.height,cachedPhysicalBounds.size.width,cachedPhysicalBounds.size.height];
 if([state isEqual:lastState])return;lastState=state;
 STHVLog(@"reflow-state",processBundle,@{@"reason":reason?:@"refresh",@"enabled":@(enabled),@"execution":@"post-launch-hosted-cache",@"scene":STHVRectJSON((STHVRect){cachedSceneBounds.origin.x,cachedSceneBounds.origin.y,cachedSceneBounds.size.width,cachedSceneBounds.size.height}),@"unmodifiedScreen":STHVRectJSON((STHVRect){cachedPhysicalBounds.origin.x,cachedPhysicalBounds.origin.y,cachedPhysicalBounds.size.width,cachedPhysicalBounds.size.height})});
}
static void refreshCache(NSString *reason){
 if(!started||!NSThread.isMainThread||refreshing)return;
 refreshing=YES;cacheEnabled=NO;
 @try{
  STHVSnapshot host={0};
  // Check authority BEFORE touching UIApplication/UIScreen. Normal full-screen
  // apps, widgets and unhosted startup need no scene traversal or screen hook.
  if(!STHVReadLayout(processBundle,&host)||!host.hosted||!host.reflowEnabled||!STHVValid(host.card))return;
  UIScreen *display=UIScreen.mainScreen;
  CGRect physical=STHVUnmodifiedScreenBounds(display);
  UIWindowScene *target=nil;
  for(UIScene *candidate in UIApplication.sharedApplication.connectedScenes){
   if(![candidate isKindOfClass:UIWindowScene.class]||candidate.activationState!=UISceneActivationStateForegroundActive)continue;
   UIWindowScene *scene=(UIWindowScene *)candidate;if(scene.screen!=display)continue;
   BOOL key=NO;for(UIWindow *window in scene.windows)if(window.isKeyWindow){key=YES;break;}
   if(!key)continue;
   if(target&&target!=scene){publishState(@"ambiguous-scenes",NO);return;}
   target=scene;
  }
  // Public scene coordinates already follow its current interface orientation.
  // No private FBS update interception and no invented frame/settings commit.
  CGRect bounds=target?target.coordinateSpace.bounds:CGRectZero;
  STHRPolicyInput policy={.inject=true,.settingMaskPresent=true,.settingBit31=host.reflowEnabled,
   .queryIsMainScreen=true,.sceneIsOnMainScreen=target&&target.screen==display,.hostedLayout=host.hosted,
   .sceneConnected=target!=nil,.sceneForegroundActive=target&&target.activationState==UISceneActivationStateForegroundActive,
   .sceneHasKeyWindow=target!=nil,.sceneBoundsValid=finiteRect(bounds),.physicalBoundsValid=finiteRect(physical),
   .sceneSize={bounds.size.width,bounds.size.height},.physicalSize={physical.size.width,physical.size.height}};
  if(!STHRShouldReflow(&policy)){publishState(@"native-scene",NO);return;}
  if(!hookInstalled){
   Method method=class_getInstanceMethod(UIScreen.class,@selector(bounds));char type[80]={0};
   if(!method||method_getNumberOfArguments(method)!=2)return;
   method_getReturnType(method,type,sizeof(type));if(strcmp(type,@encode(CGRect)))return;
   IMP previous=method_getImplementation(method);if(previous==(IMP)screenBounds)return;
   primaryDisplay=display;cachedPhysicalBounds=physical;
   nativeBounds=(void *)previous;method_setImplementation(method,(IMP)screenBounds);hookInstalled=YES;
  }
  cachedPhysicalBounds=physical;cachedSceneBounds=bounds;cacheExpires=reflowNow()+3.0;cacheEnabled=YES;
  publishState(reason,YES);
 }@catch(NSException *exception){cacheEnabled=NO;}
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
 started=YES;processBundle=[NSBundle.mainBundle.bundleIdentifier copy];
 NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
 for(NSString *name in @[UIApplicationDidBecomeActiveNotification,UISceneDidActivateNotification,UISceneWillDeactivateNotification,UISceneDidDisconnectNotification,UIWindowDidBecomeKeyNotification,UIWindowDidResignKeyNotification]){
  [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note){
   if(NSThread.isMainThread&&([note.name isEqual:UISceneWillDeactivateNotification]||[note.name isEqual:UISceneDidDisconnectNotification]||[note.name isEqual:UIWindowDidResignKeyNotification]))cacheEnabled=NO;
   scheduleRefresh(note.name);
  }];
 }
 STHVObserveLayout(processBundle,^{scheduleRefresh(@"host-layout");});
 scheduleRefresh(@"post-launch-install");
}
