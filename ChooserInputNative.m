#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdio.h>
static BOOL yesKey(id self,SEL cmd){return YES;}
static id objectCall(id value,NSString *name){
 SEL sel=NSSelectorFromString(name);NSMethodSignature *s=[value methodSignatureForSelector:sel];
 if(!s||s.numberOfArguments!=2||s.methodReturnType[0]!='@')return nil;
 return ((id(*)(id,SEL))objc_msgSend)(value,sel);
}
#include "ChooserFocusRouting.inc"
static BOOL inputScene(UIWindowScene *scene,UIScreen *screen){
 Class shell=NSClassFromString(@"SBWindowScene");
 return shell&&[scene isKindOfClass:shell]&&scene.activationState==UISceneActivationStateForegroundActive&&scene.screen==screen;
}
UIWindowScene *STHChooserInputScene(UIWindowScene *renderScene){
 if(!NSThread.isMainThread||!renderScene)return nil;
 id app=UIApplication.sharedApplication,manager=objectCall(app,@"windowSceneManager");
 id scene=objectCall(manager,@"activeDisplayWindowSceneFollowingUserInteraction");
 if(inputScene(scene,renderScene.screen))return scene;
 scene=objectCall(app,@"activeDisplayWindowScene");if(inputScene(scene,renderScene.screen))return scene;
 scene=objectCall(app,@"embeddedDisplayWindowScene");if(inputScene(scene,renderScene.screen))return scene;
 return inputScene(renderScene,renderScene.screen)?renderScene:nil;
}
UIWindow *STHCreateChooserInputWindow(UIWindowScene *scene){
 if(!NSThread.isMainThread||!scene||scene.activationState!=UISceneActivationStateForegroundActive)return nil;
 static Class windowClass;
 if(!windowClass){
  Class base=NSClassFromString(@"SBFWindow");if(!base)return nil;
  windowClass=objc_allocateClassPair(base,"STHChooserInputWindow",0);
  if(windowClass){
   const char *encoding=@encode(BOOL);
   char type[8];snprintf(type,sizeof(type),"%s@:",encoding);
   class_addMethod(windowClass,@selector(canBecomeKeyWindow),(IMP)yesKey,type);
   class_addMethod(windowClass,NSSelectorFromString(@"_canBecomeKeyWindow"),(IMP)yesKey,type);
   objc_registerClassPair(windowClass);
  }else windowClass=NSClassFromString(@"STHChooserInputWindow");
 }
 UIWindow *window=[[windowClass alloc] initWithWindowScene:scene];
 window.frame=scene.coordinateSpace.bounds;
 // The ring closes before presentation. Do not inherit the render-only host's level.
 window.windowLevel=UIWindowLevelStatusBar-1;
 window.backgroundColor=UIColor.clearColor;
 return window;
}
NSObject *STHAcquireChooserKeyboardFocus(UIWindow *window){
 if(!NSThread.isMainThread||window.hidden||window.windowScene.activationState!=UISceneActivationStateForegroundActive)return nil;
 Class workspace=NSClassFromString(@"SBMainWorkspace");
 id instance=objectCall(workspace,@"sharedInstanceIfExists")?:objectCall(workspace,@"sharedInstance");
 id controller=objectCall(instance,@"keyboardFocusController");
 return createChooserFocusToken(controller,window.windowScene,window);
}
void STHReleaseChooserKeyboardFocus(NSObject *assertion){
 invalidateFocus(assertion);
}
