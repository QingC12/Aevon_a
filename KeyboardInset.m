// Loaded privately only by SthenoKeyboard; no SpringBoard transforms are changed.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import "KeyboardInsetMath.h"
static CGFloat (*previousInset)(id,SEL,UIWindowScene *,BOOL *,BOOL);
static __unsafe_unretained id *frontmostSlot,*bundleSlot,*sceneSlot;
static unsigned char *injectedSlot;

static CGFloat correctedInset(id receiver,SEL selector,UIWindowScene *scene,BOOL *minimum,BOOL ignoreX) {
 CGFloat old=previousInset(receiver,selector,scene,minimum,ignoreX);
 if (![NSThread isMainThread]||!scene||!injectedSlot||!*injectedSlot||
     !frontmostSlot||!bundleSlot) return old;
 id front=*frontmostSlot, bundle=*bundleSlot;
 if (![front isKindOfClass:NSString.class]||![bundle isKindOfClass:NSString.class]||
     [front length]==0||[bundle length]==0||[front isEqualToString:bundle])return old;
 if (sceneSlot&&*sceneSlot&&*sceneSlot!=scene)return old;
 if (!UIInterfaceOrientationIsPortrait(scene.interfaceOrientation))return old;
 SEL ks=NSSelectorFromString(@"keyboardWindow");
 if (![receiver respondsToSelector:ks])return old;
 UIWindow *keyboard=((id(*)(id,SEL))objc_msgSend)(receiver,ks);
 if (![keyboard isKindOfClass:UIWindow.class]||keyboard.hidden||keyboard.alpha<.01)return old;
 UIWindow *target=nil;
 for(UIWindow *w in scene.windows) {
  if(w==keyboard||w.hidden||w.alpha<.01)continue;
  if([NSStringFromClass(w.class) containsString:@"Keyboard"])continue;
  if(w.isKeyWindow){target=w;break;}
  if(!target&&w.windowLevel==UIWindowLevelNormal)target=w;
 }
 if(!target||target.screen!=keyboard.screen)return old;
 // UIKit conversion accounts for window origins/transforms. Do not add the
 // legacy world-height/scene-height correction a second time.
 CGRect bounds=target.bounds;
 CGRect converted=[keyboard convertRect:keyboard.bounds toWindow:target];
 return STHReduceKeyboardInset(old,bounds.origin.x,bounds.origin.y,bounds.size.width,bounds.size.height,
    converted.origin.x,converted.origin.y,converted.size.width,converted.size.height,ignoreX);
}
static void installInset(void) {
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
