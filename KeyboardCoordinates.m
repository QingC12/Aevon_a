// Notification-based editors (comments/chat) and UIKit insets must share a single
// app-scene coordinate system. Never inspect or log input text.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
#import "KeyboardCoordinates.h"
#import "LayoutBus.h"
extern BOOL STHFloatingKeyboardScope(UIWindowScene *);
extern UIWindow *STHTargetKeyboardWindow(UIWindowScene *,UIWindow *);
static NSDictionary *(*originalInfo)(id,SEL);
static char cacheKey;
static __thread BOOL converting;
static __weak UIWindow *recentKeyboard;
static CGRect latestScreenFrame;
static CFTimeInterval latestAt;
static NSString *lastSource;
static __weak UIWindowScene *lastNormalizedScene;
static CGRect lastNormalizedEnd;
static BOOL hasNormalizedEnd;
static BOOL postingLayoutRefresh;
static NSNumber *originalKeyboardDuration,*originalKeyboardCurve;

static BOOL actualHost(UIView *view,UIWindow *target,int depth,int *remaining,CGRect *best) {
 if(!view||depth>14||--*remaining<0||view.hidden||view.alpha<.01)return NO;
 NSString *name=NSStringFromClass(view.class);
 BOOL host=[name containsString:@"InputSetHost"]||[name containsString:@"RemoteKeyboardPlaceholder"];
 BOOL found=NO;
 if(host){
  CGRect r=[view convertRect:view.bounds toView:target];double overlap=0;
  if(CGRectGetWidth(r)>=CGRectGetWidth(target.bounds)*.7 &&
    CGRectGetHeight(r)>=60 && STHLocalKeyboardOverlap(target.bounds.origin.x,target.bounds.origin.y,
     target.bounds.size.width,target.bounds.size.height,r.origin.x,r.origin.y,r.size.width,r.size.height,NO,&overlap)){
   if(CGRectIsNull(*best)||CGRectGetHeight(r)>CGRectGetHeight(*best))*best=r;
   found=YES;
  }
 }
 for(UIView *child in view.subviews){if(*remaining<=0)break;found=actualHost(child,target,depth+1,remaining,best)||found;}
 return found;
}
static UIWindow *existingKeyboard(UIWindowScene *scene) {
 UIWindow *known=recentKeyboard;if(known&&!known.hidden)return known;
 Class cls=NSClassFromString(@"UIRemoteKeyboardWindow");
 SEL method=NSSelectorFromString(@"remoteKeyboardWindowForScreen:create:");
 if([cls respondsToSelector:method]){
  id w=((id(*)(id,SEL,UIScreen *,BOOL))objc_msgSend)(cls,method,scene.screen,NO);
  if([w isKindOfClass:UIWindow.class])return w;
 }
 return nil;
}

BOOL STHResolveKeyboard(UIWindowScene *scene,UIWindow *keyboard,CGRect raw,BOOL ignoreX,
 CGRect *local,double *overlap,UIWindow **targetOut) {
 if(!STHFloatingKeyboardScope(scene))return NO;
 if(!keyboard)keyboard=existingKeyboard(scene);
 if(keyboard)recentKeyboard=keyboard;
 UIWindow *target=STHTargetKeyboardWindow(scene,keyboard);
 if(!target)return NO;
 CGRect mapped=CGRectNull;
 if(STHReadLayout(NSBundle.mainBundle.bundleIdentifier,target.bounds,&mapped,overlap)){
  lastSource=@"hosted-card-scale-and-origin";
  if(local)*local=mapped;if(targetOut)*targetOut=target;
  return YES;
 }
 CGRect r=CGRectNull;
 if(keyboard&&!keyboard.hidden&&keyboard.alpha>.01){
  int remaining=512;actualHost(keyboard,target,0,&remaining,&r);
 }
 if(!CGRectIsNull(r))lastSource=@"keyboard-host";
 else {
  if(CGRectIsNull(raw)){
   if(CACurrentMediaTime()-latestAt>3)return NO;
   raw=latestScreenFrame;
  }
  UIScreen *screen=target.screen;
  double nativeScale=screen.nativeScale;
  if(nativeScale<=0)return NO;
  double physicalW=screen.nativeBounds.size.width/nativeScale;
  double physicalH=screen.nativeBounds.size.height/nativeScale;
  if(!STHPhysicalFrame(raw.origin.x,raw.origin.y,raw.size.width,raw.size.height,physicalW,physicalH))return NO;
  // Physical screen is NOT UIScreen.bounds, which the original tweak virtualizes.
  r=[target convertRect:raw fromCoordinateSpace:screen.fixedCoordinateSpace];
  lastSource=@"physical-screen-to-window";
 }
 CGRect b=target.bounds;
 if(!STHLocalKeyboardOverlap(b.origin.x,b.origin.y,b.size.width,b.size.height,
    r.origin.x,r.origin.y,r.size.width,r.size.height,ignoreX,overlap))return NO;
 if(local)*local=r;if(targetOut)*targetOut=target;
 return YES;
}

static void recordLayout(UIWindowScene *scene,CGRect incoming,CGRect local,double inset) {
 static CFTimeInterval last=0;CFTimeInterval now=CACurrentMediaTime();
 if(now-last<.25)return;last=now;
 STHWriteLayoutLog([NSString stringWithFormat:@"app scene=%@ incoming=%@ local=%@ inset=%.2f source=%@",
  NSStringFromCGRect(scene.coordinateSpace.bounds),NSStringFromCGRect(incoming),NSStringFromCGRect(local),inset,lastSource]);
 if(inset>=0)STHReportLayout(NSBundle.mainBundle.bundleIdentifier,inset,YES);
}

static NSDictionary *normalizedInfo(NSNotification *note,SEL selector) {
 NSDictionary *raw=originalInfo(note,selector);
 if(converting||![NSThread isMainThread]||![raw isKindOfClass:NSDictionary.class])return raw;
 NSString *name=note.name;
 if([name isEqualToString:UIKeyboardWillHideNotification]||[name isEqualToString:UIKeyboardDidHideNotification]){
  latestAt=0;latestScreenFrame=CGRectNull;hasNormalizedEnd=NO;return raw;
 }
 BOOL visible=[name isEqualToString:UIKeyboardWillShowNotification]||[name isEqualToString:UIKeyboardDidShowNotification]||
  [name isEqualToString:UIKeyboardWillChangeFrameNotification]||[name isEqualToString:UIKeyboardDidChangeFrameNotification];
 if(!visible)return raw;
 if(!postingLayoutRefresh){
  if([raw[UIKeyboardAnimationDurationUserInfoKey] isKindOfClass:NSNumber.class])originalKeyboardDuration=raw[UIKeyboardAnimationDurationUserInfoKey];
  if([raw[UIKeyboardAnimationCurveUserInfoKey] isKindOfClass:NSNumber.class])originalKeyboardCurve=raw[UIKeyboardAnimationCurveUserInfoKey];
 }
 NSDictionary *cached=objc_getAssociatedObject(note,&cacheKey);if(cached)return cached;
 id value=raw[UIKeyboardFrameEndUserInfoKey];if(![value isKindOfClass:NSValue.class])return raw;
 converting=YES;
 NSDictionary *result=raw;
 @try{
  CGRect incoming=[value CGRectValue];
  for(UIScene *s in UIApplication.sharedApplication.connectedScenes){
   if(![s isKindOfClass:UIWindowScene.class])continue;
   UIWindowScene *scene=(UIWindowScene *)s;
   if(!STHFloatingKeyboardScope(scene))continue;
   CGRect local=CGRectNull;double overlap=0;UIWindow *target=nil;
   if(!STHResolveKeyboard(scene,nil,incoming,NO,&local,&overlap,&target)){
    lastSource=@"fallback-unresolved";recordLayout(scene,incoming,CGRectNull,-1);continue;
   }
   // Deliver the physical keyboard's app-scene frame, not a screen-height based
   // rectangle. Both direct notification handlers and UIKit see this result.
   CGRect frame=[scene.coordinateSpace convertRect:local fromCoordinateSpace:target];
   NSMutableDictionary *updated=[raw mutableCopy];
   updated[UIKeyboardFrameEndUserInfoKey]=[NSValue valueWithCGRect:frame];
   id beginValue=raw[UIKeyboardFrameBeginUserInfoKey];
   if([lastSource isEqualToString:@"hosted-card-scale-and-origin"]){
    CGRect begin=frame;
    if(hasNormalizedEnd&&lastNormalizedScene==scene)begin=lastNormalizedEnd;
    else begin.origin.y=CGRectGetMaxY(scene.coordinateSpace.bounds);
    updated[UIKeyboardFrameBeginUserInfoKey]=[NSValue valueWithCGRect:begin];
   } else if([beginValue isKindOfClass:NSValue.class]){
    CGRect begin=[beginValue CGRectValue];
    UIScreen *screen=target.screen;double scale=screen.nativeScale;
    double physicalW=scale>0?screen.nativeBounds.size.width/scale:0;
    if(isfinite(begin.origin.x)&&isfinite(begin.origin.y)&&isfinite(begin.size.width)&&isfinite(begin.size.height)
       &&physicalW>1&&begin.size.width>=physicalW*.7&&begin.size.height>0){
     CGRect b=[scene.coordinateSpace convertRect:begin fromCoordinateSpace:screen.fixedCoordinateSpace];
     updated[UIKeyboardFrameBeginUserInfoKey]=[NSValue valueWithCGRect:b];
    }
   }
   // Avoid mixing corrected end frame with stale legacy keyboard bounds.
   if(updated[@"UIKeyboardBoundsUserInfoKey"])
    updated[@"UIKeyboardBoundsUserInfoKey"]=[NSValue valueWithCGRect:CGRectMake(0,0,frame.size.width,frame.size.height)];
   lastNormalizedScene=scene;lastNormalizedEnd=frame;hasNormalizedEnd=YES;
   result=[updated copy];objc_setAssociatedObject(note,&cacheKey,result,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
   latestScreenFrame=incoming;latestAt=CACurrentMediaTime();
   recordLayout(scene,incoming,local,overlap);break;
  }
 }@catch(NSException *e){result=raw;}
 converting=NO;return result;
}

static void refreshHostedLayout(void) {
 if(postingLayoutRefresh||![NSThread isMainThread])return;
 for(UIScene *s in UIApplication.sharedApplication.connectedScenes){
  if(![s isKindOfClass:UIWindowScene.class])continue;
  UIWindowScene *scene=(UIWindowScene *)s;
  if(!STHFloatingKeyboardScope(scene))continue;
  UIWindow *window=STHTargetKeyboardWindow(scene,nil);if(!window)continue;
  CGRect local;double overlap=0;
  if(!STHReadLayout(NSBundle.mainBundle.bundleIdentifier,window.bounds,&local,&overlap))continue;
  CGRect end=[scene.coordinateSpace convertRect:local fromCoordinateSpace:window];
  if(hasNormalizedEnd&&lastNormalizedScene==scene&&
     fabs(end.origin.y-lastNormalizedEnd.origin.y)<.75&&fabs(end.size.height-lastNormalizedEnd.size.height)<.75&&
     fabs(end.origin.x-lastNormalizedEnd.origin.x)<.75&&fabs(end.size.width-lastNormalizedEnd.size.width)<.75)return;
  CGRect begin=hasNormalizedEnd&&lastNormalizedScene==scene?lastNormalizedEnd:end;
  postingLayoutRefresh=YES;
  @try{
   // Reissue only geometry changes when the host's animated final frame settles.
   // No extra show/hide, no input events, and no native library code patch.
   [NSNotificationCenter.defaultCenter postNotificationName:UIKeyboardWillChangeFrameNotification object:nil
    userInfo:@{UIKeyboardFrameBeginUserInfoKey:[NSValue valueWithCGRect:begin],
               UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:end],
               UIKeyboardAnimationDurationUserInfoKey:originalKeyboardDuration?:@0.25,
               UIKeyboardAnimationCurveUserInfoKey:originalKeyboardCurve?:@7,UIKeyboardIsLocalUserInfoKey:@YES}];
  }@catch(NSException *e){}
  postingLayoutRefresh=NO;
  STHReportLayout(NSBundle.mainBundle.bundleIdentifier,overlap,YES);
  return;
 }
}

void STHInstallKeyboardNotifications(void) {
 Class concrete=object_getClass([NSNotification notificationWithName:@"stheno.layout.probe" object:nil userInfo:@{}]);
 Method m=class_getInstanceMethod(concrete,@selector(userInfo));if(!m)return;
 IMP old=method_getImplementation(m);if(old==(IMP)normalizedInfo)return;
 originalInfo=(void *)old;method_setImplementation(m,(IMP)normalizedInfo);
 STHObserveLayout(NSBundle.mainBundle.bundleIdentifier,^{refreshHostedLayout();});
 STHWriteLayoutLog(@"notification adapter ready; physical-card coordinate channel registered");
}
