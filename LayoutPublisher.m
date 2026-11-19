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
static CGRect previousCard,previousKeyboard;
static NSString *physicalSource;
static CFTimeInterval keyboardFrameAt;
static id keyboardFrameObserver;
static BOOL usableKeyboard(CGRect r,CGRect screen) {
 return isfinite(r.origin.x)&&isfinite(r.origin.y)&&isfinite(r.size.width)&&isfinite(r.size.height)&&
  r.size.width>=screen.size.width*.7&&r.size.height>=60&&r.size.height<screen.size.height*.7&&
  fabs(CGRectGetMaxY(r)-CGRectGetMaxY(screen))<=10;
}

static BOOL physicalKeyboardHost(UIView *v,UIScreen *screen,int depth,int *budget,CGRect *best) {
 if(!v||v.hidden||v.alpha<.01||depth>14||--*budget<0)return NO;
 NSString *name=NSStringFromClass(v.class);BOOL found=NO;
 if([name containsString:@"InputSetHost"]||[name containsString:@"RemoteKeyboardPlaceholder"]||
    [name containsString:@"InputSetContainer"]){
  CGRect r=[v convertRect:v.bounds toCoordinateSpace:screen.fixedCoordinateSpace];
  CGRect b=screen.bounds;
  if(usableKeyboard(r,b)){
   *best=CGRectIsNull(*best)?r:CGRectUnion(*best,r);found=YES;
  }
 }
 for(UIView *child in v.subviews){if(*budget<=0)break;found=physicalKeyboardHost(child,screen,depth+1,budget,best)||found;}
 return found;
}
static void includeVisibleAccessories(UIView *view,UIScreen *screen,int depth,int *budget,CGRect *assembly) {
 if(!view||view.hidden||view.alpha<.01||depth>14||--*budget<0)return;
 NSString *name=NSStringFromClass(view.class).lowercaseString;
 if([name containsString:@"accessory"]||[name containsString:@"assistant"]||
    [name containsString:@"candidate"]||[name containsString:@"prediction"]||[name containsString:@"toolbar"]){
  CGRect r=[view convertRect:view.bounds toCoordinateSpace:screen.fixedCoordinateSpace];
  double join=fabs(CGRectGetMaxY(r)-CGRectGetMinY(*assembly));
  if(r.size.width>=screen.bounds.size.width*.7&&r.size.height>=10&&r.size.height<=160&&
     r.origin.y>=0&&r.origin.y<=assembly->origin.y&&join<=8){
   *assembly=CGRectUnion(*assembly,r);
  }
 }
 for(UIView *child in view.subviews){if(*budget<=0)break;includeVisibleAccessories(child,screen,depth+1,budget,assembly);}
}
static CGRect currentKeyboard(void) {
 UIScreen *s=UIScreen.mainScreen;Class cls=NSClassFromString(@"UIRemoteKeyboardWindow");
 SEL selector=NSSelectorFromString(@"remoteKeyboardWindowForScreen:create:");
 if([cls respondsToSelector:selector]){
  id w=((id(*)(id,SEL,UIScreen *,BOOL))objc_msgSend)(cls,selector,s,NO);
  if([w isKindOfClass:UIWindow.class]){int budget=512;CGRect r=CGRectNull;
   if(physicalKeyboardHost(w,s,0,&budget,&r)){
    // Use the CURRENT visible assembly, never a minimum of historical frames.
    // Native notifications can legitimately switch 563->590 as candidate UI
    // changes; a stale union makes one app high and the next app obscured.
    int accessoryBudget=512;includeVisibleAccessories(w,s,0,&accessoryBudget,&r);
    physicalSource=@"visible-keyboard-assembly";
    return r;
   }
  }
 }
 physicalSource=@"native-physical-notification";
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
 if(now-lastLog>1||!CGRectEqualToRect(previousCard,card)||!CGRectEqualToRect(previousKeyboard,keyboard)){
  lastLog=now;previousCard=card;previousKeyboard=keyboard;
  STHWriteLayoutLog([NSString stringWithFormat:@"host bundle=%@ card=%@ keyboard=%@ transport=%@ source=%@ native=%@ age=%.3f",
   observedBundle,NSStringFromCGRect(card),NSStringFromCGRect(keyboard),ok?@"ok":@"failed",physicalSource,NSStringFromCGRect(keyboardFrame),now-keyboardFrameAt]);
 }
}
void STHStartLayout(void *model,CGRect keyboard) {
 if(![NSThread isMainThread]||!model)return;
 NSString *bundle=STHNativeCopyBundleID(model);
 if(![bundle isKindOfClass:NSString.class]||bundle.length==0)return;
 if(observedBundle&&![observedBundle isEqualToString:bundle])STHPublishLayout(observedBundle,CGRectZero,CGRectZero,NO);
 observedModel=(__bridge id)model;observedBundle=bundle;keyboardFrame=keyboard;
 keyboardFrameAt=CACurrentMediaTime();
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
 keyboardFrame=CGRectNull;keyboardFrameAt=0;previousKeyboard=CGRectNull;
}

__attribute__((constructor)) static void layoutPublisherReady(void) {
 dispatch_async(dispatch_get_main_queue(),^{
  STHWriteLayoutLog(@"stheno 2.0.8 host layout publisher initialized (app adapter excluded)");
  keyboardFrameObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardWillChangeFrameNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
   if(!observedModel)return;
   id value=note.userInfo[UIKeyboardFrameEndUserInfoKey];
   if([value isKindOfClass:NSValue.class]){
    CGRect r=[value CGRectValue];
    if(usableKeyboard(r,UIScreen.mainScreen.bounds)){keyboardFrame=r;keyboardFrameAt=CACurrentMediaTime();publishCurrent();}
   }
  }];
 });
}
