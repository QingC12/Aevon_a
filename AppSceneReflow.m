// Screen-size compatibility only. No keyboard/window geometry or URL hooks.
#import "AppSceneReflow.h"
#import "AppSceneReflowPolicy.h"
#import "ViewportDiagnostics.h"
#import "ViewportBus.h"
#import <objc/runtime.h>
#import <string.h>
extern BOOL STHVSceneIsHosted(void);
static CGRect (*nativeBounds)(id,SEL);
static void (*nativeSceneUpdate)(id,SEL,id,id,id,id);
static BOOL hooksInstalled,injectEnabled,maskPresent,bit31,hostedLayout;
static double hostedCheckedAt;
static NSString *processBundle,*lastState;
static __thread BOOL evaluating;
static void refreshPolicy(void){
 NSDictionary *domain=[NSUserDefaults.standardUserDefaults persistentDomainForName:@"com.nx.stheno"];
 id inject=domain[@"Inject"],mask=domain[@"SettingMask"];
 injectEnabled=![inject isKindOfClass:NSNumber.class]||[inject boolValue];
 maskPresent=[mask isKindOfClass:NSNumber.class];
 bit31=maskPresent&&([mask unsignedLongLongValue]&(1ULL<<31))!=0;
 hostedLayout=STHVSceneIsHosted();hostedCheckedAt=NSProcessInfo.processInfo.systemUptime;
}
CGRect STHVUnmodifiedScreenBounds(UIScreen *screen){
 if(!screen)return CGRectZero;
 return nativeBounds?nativeBounds(screen,@selector(bounds)):screen.bounds;
}
static BOOL validRect(CGRect r){return isfinite(r.origin.x)&&isfinite(r.origin.y)&&isfinite(r.size.width)&&isfinite(r.size.height)&&r.size.width>0&&r.size.height>0;}
static UIWindowScene *targetScene(UIScreen *screen){
 UIWindowScene *target=nil;
 for(UIScene *candidate in UIApplication.sharedApplication.connectedScenes){
  if(![candidate isKindOfClass:UIWindowScene.class]||candidate.activationState!=UISceneActivationStateForegroundActive)continue;
  UIWindowScene *scene=(UIWindowScene *)candidate;if(scene.screen!=screen)continue;
  BOOL key=NO;for(UIWindow *w in scene.windows)if(w.isKeyWindow){key=YES;break;}
  if(!key)continue;
  if(target&&target!=scene)return nil; // Ambiguous multi-scene layouts stay native.
  target=scene;
 }
 return target;
}
static CGRect sceneBounds(UIWindowScene *scene){
 SEL selector=NSSelectorFromString(@"_boundsForInterfaceOrientation:");
 Method m=class_getInstanceMethod(object_getClass(scene),selector);
 char result[80]={0},argument[16]={0};
 if(!m||method_getNumberOfArguments(m)!=3||scene.interfaceOrientation==UIInterfaceOrientationUnknown)return CGRectZero;
 method_getReturnType(m,result,sizeof(result));method_getArgumentType(m,2,argument,sizeof(argument));
 if(strcmp(result,@encode(CGRect))||(argument[0]!='q'&&argument[0]!='Q'))return CGRectZero;
 return ((CGRect(*)(id,SEL,UIInterfaceOrientation))method_getImplementation(m))(scene,selector,scene.interfaceOrientation);
}
static BOOL decision(UIScreen *screen,CGRect *virtualBounds,CGRect *physicalBounds){
 CGRect physical=STHVUnmodifiedScreenBounds(UIScreen.mainScreen),bounds=CGRectZero;
 UIWindowScene *scene=targetScene(screen);if(scene)bounds=sceneBounds(scene);
 BOOL hosted=hostedLayout&&NSProcessInfo.processInfo.systemUptime-hostedCheckedAt<=3.0;
 STHRPolicyInput input={.inject=injectEnabled,.settingMaskPresent=maskPresent,.settingBit31=bit31,
  .queryIsMainScreen=screen==UIScreen.mainScreen,.sceneIsOnMainScreen=scene&&scene.screen==UIScreen.mainScreen,
  .hostedLayout=hosted,.sceneConnected=scene!=nil,.sceneForegroundActive=scene&&scene.activationState==UISceneActivationStateForegroundActive,
  .sceneHasKeyWindow=scene!=nil,.sceneBoundsValid=validRect(bounds),.physicalBoundsValid=validRect(physical),
  .sceneSize={bounds.size.width,bounds.size.height},.physicalSize={physical.size.width,physical.size.height}};
 if(virtualBounds)*virtualBounds=bounds;if(physicalBounds)*physicalBounds=physical;
 return STHRShouldReflow(&input);
}
static CGRect screenBounds(id screen,SEL selector){
 CGRect original=nativeBounds(screen,selector);
 if(evaluating||!NSThread.isMainThread||screen!=UIScreen.mainScreen)return original;
 evaluating=YES;
 @try{CGRect virtualBounds;if(decision(screen,&virtualBounds,NULL))return virtualBounds;return original;}
 @finally{evaluating=NO;}
}
static void logPolicy(NSString *reason){
 if(!NSThread.isMainThread||evaluating)return;
 evaluating=YES;
 @try{
  CGRect virtualBounds,physical;BOOL enabled=decision(UIScreen.mainScreen,&virtualBounds,&physical);
  NSString *state=[NSString stringWithFormat:@"%d/%d/%d/%d/%.2f/%.2f/%.2f/%.2f",enabled,injectEnabled,maskPresent,bit31,virtualBounds.size.width,virtualBounds.size.height,physical.size.width,physical.size.height];
  if([lastState isEqual:state])return;lastState=state;
  STHVLog(@"reflow-state",processBundle,@{@"reason":reason,@"enabled":@(enabled),@"inject":@(injectEnabled),@"settingMaskPresent":@(maskPresent),@"bit31":@(bit31),@"hosted":@(STHVSceneIsHosted()),@"scene":STHVRectJSON((STHVRect){virtualBounds.origin.x,virtualBounds.origin.y,virtualBounds.size.width,virtualBounds.size.height}),@"unmodifiedScreen":STHVRectJSON((STHVRect){physical.origin.x,physical.origin.y,physical.size.width,physical.size.height})});
 }@finally{evaluating=NO;}
}
static void sceneUpdate(id self,SEL selector,id identifier,id diff,id transition,id completion){
 if(NSThread.isMainThread)refreshPolicy();
 // Evaluate the current native scene each getter invocation, including while
 // UIKit applies this diff. Do not cache an instance or invent an ID mapping.
 nativeSceneUpdate(self,selector,identifier,diff,transition,completion);
 if(NSThread.isMainThread)logPolicy(@"scene-update");
}
void STHVInstallAppSceneReflow(void){
 if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{STHVInstallAppSceneReflow();});return;}
 if(hooksInstalled)return;
 processBundle=NSBundle.mainBundle.bundleIdentifier;
 if(!processBundle.length||[processBundle isEqual:@"com.apple.springboard"]||[processBundle isEqual:@"com.apple.UIKit.remote-keyboard"]||[processBundle isEqual:@"com.apple.Spotlight"])return;
 refreshPolicy();
 Method m=class_getInstanceMethod(UIScreen.class,@selector(bounds));char type[80]={0};
 if(m)method_getReturnType(m,type,sizeof(type));
 if(!m||method_getNumberOfArguments(m)!=2||strcmp(type,@encode(CGRect)))return;
 nativeBounds=(void *)method_getImplementation(m);method_setImplementation(m,(IMP)screenBounds);
 hooksInstalled=YES;
 Class client=NSClassFromString(@"FBSWorkspaceScenesClient");SEL selector=NSSelectorFromString(@"sceneID:updateWithSettingsDiff:transitionContext:completion:");
 Method update=class_getInstanceMethod(client,selector);char result[16]={0};BOOL valid=update&&method_getNumberOfArguments(update)==6;
 if(valid){method_getReturnType(update,result,sizeof(result));valid=result[0]=='v';}
 for(unsigned i=2;valid&&i<6;i++){char argument[16]={0};method_getArgumentType(update,i,argument,sizeof(argument));valid=argument[0]=='@';}
 if(valid){nativeSceneUpdate=(void *)method_getImplementation(update);method_setImplementation(update,(IMP)sceneUpdate);}
 NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
 for(NSString *name in @[NSUserDefaultsDidChangeNotification,UIApplicationDidBecomeActiveNotification,UISceneDidActivateNotification,UISceneWillDeactivateNotification,UISceneDidDisconnectNotification]){
  [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){refreshPolicy();logPolicy(note.name);}];
 }
 STHVObserveLayout(processBundle,^{refreshPolicy();logPolicy(@"host-layout");});
 logPolicy(@"module-start");
}
__attribute__((constructor)) static void installSceneReflow(void){STHVInstallAppSceneReflow();}
