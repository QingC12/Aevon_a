// Loaded privately only by SthenoKeyboard; no SpringBoard transforms are changed.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import "LayoutBus.h"
extern BOOL STHResolveKeyboard(UIWindowScene *,UIWindow *,CGRect,BOOL,CGRect *,double *,UIWindow **);
extern BOOL STHResolveKeyboardScene(UIWindowScene *,UIWindow *,CGRect,BOOL,CGRect *,double *);
extern void STHInstallKeyboardNotifications(void);
static CGFloat (*previousInset)(id,SEL,UIWindowScene *,BOOL *,BOOL);
static __unsafe_unretained id *frontmostSlot,*bundleSlot,*sceneSlot;
static unsigned char *injectedSlot;

BOOL STHFloatingKeyboardScope(UIWindowScene *scene) {
 NSString *process=NSBundle.mainBundle.bundleIdentifier;
 // The UIKit-filtered original library also loads in SpringBoard. Never let
 // the APP adapter rewrite the physical keyboard publisher's notifications.
 if([process isEqualToString:@"com.apple.springboard"]||
    [process isEqualToString:@"com.apple.UIKit.remote-keyboard"]||
    [process isEqualToString:@"com.apple.Spotlight"])return NO;
 if(![NSThread isMainThread]||!scene||!UIInterfaceOrientationIsPortrait(scene.interfaceOrientation))return NO;
 // Correct only while the host confirms this specific app is floated and its
 // keyboard is active. A stale cached frontmost flag cannot keep it enabled.
 return STHLayoutStatus(NSBundle.mainBundle.bundleIdentifier)>0;
}

static BOOL containsEditorFocus(UIView *view,int depth,int *budget){
 if(!view||view.hidden||view.alpha<.01||depth>18||--*budget<0)return NO;
 if(view.isFirstResponder)return YES;
 for(UIView *child in view.subviews)if(containsEditorFocus(child,depth+1,budget))return YES;
 return NO;
}
UIWindow *STHTargetKeyboardWindow(UIWindowScene *scene,UIWindow *keyboard) {
 UIWindow *target=nil,*key=nil;
 for(UIWindow *w in scene.windows){
  if(w==keyboard||w.hidden||w.alpha<.01)continue;
  if([NSStringFromClass(w.class) containsString:@"Keyboard"])continue;
  int budget=1200;if(containsEditorFocus(w,0,&budget))return w;
  if(w.isKeyWindow)key=w;
  if(!target&&w.windowLevel==UIWindowLevelNormal)target=w;
 }
 return key?:target;
}

static CGFloat correctedInset(id receiver,SEL selector,UIWindowScene *scene,BOOL *minimum,BOOL ignoreX) {
 CGFloat old=previousInset(receiver,selector,scene,minimum,ignoreX);
 if(!STHFloatingKeyboardScope(scene))return old;
 if(STHLayoutStatus(NSBundle.mainBundle.bundleIdentifier)==2)return old;
 SEL ks=NSSelectorFromString(@"keyboardWindow");
 UIWindow *keyboard=nil;
 if([receiver respondsToSelector:ks])keyboard=((id(*)(id,SEL))objc_msgSend)(receiver,ks);
 if(![keyboard isKindOfClass:UIWindow.class])keyboard=nil;
 CGRect local=CGRectNull;double overlap=0;
 // Unlike 2.0.4, measure the actual InputSetHost/placeholder rather than using
 // the full-screen keyboard WINDOW as though its entire bounds were keys.
 @try{
  // This API is explicitly FOR A WINDOW SCENE, not for its key/popup window.
  // Returning an extra window-origin delta here causes the observed 45pt lift.
  if(STHResolveKeyboardScene(scene,keyboard,CGRectNull,ignoreX,&local,&overlap)){
   if(minimum)*minimum=overlap<=0;
   return overlap;
  }
 }@catch(NSException *exception){}
 return old;
}
static void installInset(void) {
 NSString *process=NSBundle.mainBundle.bundleIdentifier;
 if([process isEqualToString:@"com.apple.springboard"]||
    [process isEqualToString:@"com.apple.UIKit.remote-keyboard"]||
    [process isEqualToString:@"com.apple.Spotlight"])return;
 void *handle=NULL;
 for(uint32_t i=0;i<_dyld_image_count();i++) {
  const char *name=_dyld_get_image_name(i);
  if(name&&[[[NSString stringWithUTF8String:name] lastPathComponent] isEqualToString:@"SthenoKeyboard.dylib"]){
   handle=dlopen(name,RTLD_LAZY|RTLD_NOLOAD);break;
  }
 }
 if(!handle)return;
 frontmostSlot=(__unsafe_unretained id *)dlsym(handle,"frontMost");
 bundleSlot=(__unsafe_unretained id *)dlsym(handle,"bundleId");
 sceneSlot=(__unsafe_unretained id *)dlsym(handle,"appScene");
 injectedSlot=dlsym(handle,"injectApp");
 STHInstallKeyboardNotifications();
 Class cls=NSClassFromString(@"_UIRemoteKeyboards");
 SEL selector=NSSelectorFromString(@"intersectionHeightForWindowScene:isLocalMinimumHeightOut:ignoreHorizontalOffset:");
 Method method=class_getInstanceMethod(cls,selector);
 if(!method||!frontmostSlot||!bundleSlot||!injectedSlot)return;
 previousInset=(void *)method_getImplementation(method);
 if(previousInset==(void *)correctedInset)return;
 method_setImplementation(method,(IMP)correctedInset);

}
__attribute__((constructor)) static void startInset(void) {
 // Run after the original dylib has installed its hooks and initialized state.
 dispatch_async(dispatch_get_main_queue(),^{installInset();});
}
