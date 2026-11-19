// SpringBoard side: publish only the active floating application's physical
// card and keyboard rectangles. No app input or message contents are read.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import "LayoutBus.h"
extern NSString *STHNativeCopyBundleID(void *) NS_RETURNS_RETAINED;
extern CGRect STHNativeRect(void *);
extern NSUInteger STHNativeOrientation(void *);
extern void STHNativeRefreshGeometry(void *);
static __weak id observedModel;
static NSString *observedBundle;
static CGRect keyboardFrame;
static dispatch_source_t layoutTimer;
static CFTimeInterval lastLog;
static CGRect previousCard;

static BOOL physicalKeyboardHost(UIView *v,UIScreen *screen,int depth,int *budget,CGRect *best) {
 if(!v||v.hidden||v.alpha<.01||depth>14||--*budget<0)return NO;
 NSString *name=NSStringFromClass(v.class);BOOL found=NO;
 if([name containsString:@"InputSetHost"]||[name containsString:@"RemoteKeyboardPlaceholder"]){
  CGRect r=[v convertRect:v.bounds toCoordinateSpace:screen.fixedCoordinateSpace];
  CGRect b=screen.bounds;
  if(r.size.width>=b.size.width*.7&&r.size.height>=60&&r.size.height<b.size.height*.7&&
     fabs(CGRectGetMaxY(r)-CGRectGetMaxY(b))<=10){*best=r;found=YES;}
 }
 for(UIView *child in v.subviews){if(*budget<=0)break;found=physicalKeyboardHost(child,screen,depth+1,budget,best)||found;}
 return found;
}
static CGRect currentKeyboard(void) {
 UIScreen *s=UIScreen.mainScreen;Class cls=NSClassFromString(@"UIRemoteKeyboardWindow");
 SEL selector=NSSelectorFromString(@"remoteKeyboardWindowForScreen:create:");
 if([cls respondsToSelector:selector]){
  id w=((id(*)(id,SEL,UIScreen *,BOOL))objc_msgSend)(cls,selector,s,NO);
  if([w isKindOfClass:UIWindow.class]){int budget=512;CGRect r=CGRectNull;
   if(physicalKeyboardHost(w,s,0,&budget,&r))return r;
  }
 }
 return keyboardFrame;
}
static void publishCurrent(void) {
 id strong=observedModel;if(!strong||!observedBundle)return;
 void *m=(__bridge void *)strong;
 if(STHNativeOrientation(m)!=1){STHPublishLayout(observedBundle,CGRectZero,CGRectZero,NO);return;}
 STHNativeRefreshGeometry(m);
 // finalFrame already includes finalScale (native 0x9c73c-0x9c758).
 // Do not multiply it again: NativeRect uses that finalFrame and finalOffset.
 CGRect card=STHNativeRect(m),keyboard=currentKeyboard();
 BOOL ok=STHPublishLayout(observedBundle,card,keyboard,YES);
 CFTimeInterval now=CACurrentMediaTime();
 if(now-lastLog>1||!CGRectEqualToRect(previousCard,card)){
  lastLog=now;previousCard=card;
  STHWriteLayoutLog([NSString stringWithFormat:@"host bundle=%@ card=%@ keyboard=%@ transport=%@",
   observedBundle,NSStringFromCGRect(card),NSStringFromCGRect(keyboard),ok?@"ok":@"failed"]);
 }
}
void STHStartLayout(void *model,CGRect keyboard) {
 if(![NSThread isMainThread]||!model)return;
 NSString *bundle=STHNativeCopyBundleID(model);
 if(![bundle isKindOfClass:NSString.class]||bundle.length==0)return;
 if(observedBundle&&![observedBundle isEqualToString:bundle])STHPublishLayout(observedBundle,CGRectZero,CGRectZero,NO);
 observedModel=(__bridge id)model;observedBundle=bundle;keyboardFrame=keyboard;
 publishCurrent();
 if(!layoutTimer){
  layoutTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
  dispatch_source_set_timer(layoutTimer,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),100*NSEC_PER_MSEC,20*NSEC_PER_MSEC);
  dispatch_source_set_event_handler(layoutTimer,^{publishCurrent();});dispatch_resume(layoutTimer);
 }
}
void STHUpdateLayout(void) { if([NSThread isMainThread])publishCurrent(); }
void STHStopLayout(void) {
 if(layoutTimer){dispatch_source_cancel(layoutTimer);layoutTimer=nil;}
 if(observedBundle){
  STHPublishLayout(observedBundle,CGRectZero,CGRectZero,NO);
  STHWriteLayoutLog([NSString stringWithFormat:@"host-hide bundle=%@",observedBundle]);
 }
 observedModel=nil;observedBundle=nil;
}
