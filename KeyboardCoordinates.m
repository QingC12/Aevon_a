// Canonical keyboard geometry for app-scene queries and notification consumers.
// This module is never installed in SpringBoard or the keyboard service.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
#import "KeyboardCoordinates.h"
#import "KeyboardSession.h"
#import "LayoutBus.h"
extern BOOL STHFloatingKeyboardScope(UIWindowScene *);
extern UIWindow *STHTargetKeyboardWindow(UIWindowScene *,UIWindow *);
static NSDictionary *(*originalInfo)(id,SEL);
static char cachedInfoKey,normalizedKey;
static __thread BOOL converting;
static __weak UIWindow *recentKeyboard;
static __weak UIWindowScene *sessionScene,*lastHideScene;
static STHKeyboardSession session;
static BOOL postingLayoutRefresh;
static NSNumber *originalDuration,*originalCurve;
static NSString *resolutionSource;
static NSDictionary *lastRealMetadata;

static STHRect rectValue(CGRect r) { return (STHRect){r.origin.x,r.origin.y,r.size.width,r.size.height}; }
static CGRect cgRect(STHRect r) { return CGRectMake(r.x,r.y,r.w,r.h); }
static CGRect canonical(CGRect bounds,CGRect raw) { return cgRect(STHOcclusionFrame(rectValue(bounds),rectValue(raw))); }

static BOOL actualHost(UIView *view,UIWindow *target,int depth,int *remaining,CGRect *best) {
 if(!view||depth>14||--*remaining<0||view.hidden||view.alpha<.01)return NO;
 NSString *name=NSStringFromClass(view.class);
 BOOL host=[name containsString:@"InputSetHost"]||[name containsString:@"RemoteKeyboardPlaceholder"]||[name containsString:@"InputSetContainer"];
 BOOL found=NO;
 if(host){
  CGRect r=[view convertRect:view.bounds toView:target];double overlap=0;
  if(CGRectGetWidth(r)>=CGRectGetWidth(target.bounds)*.7&&CGRectGetHeight(r)>=60&&
     STHLocalKeyboardOverlap(target.bounds.origin.x,target.bounds.origin.y,target.bounds.size.width,target.bounds.size.height,
        r.origin.x,r.origin.y,r.size.width,r.size.height,NO,&overlap)){
   *best=CGRectIsNull(*best)?r:CGRectUnion(*best,r);found=YES;
  }
 }
 for(UIView *child in view.subviews){if(*remaining<=0)break;found=actualHost(child,target,depth+1,remaining,best)||found;}
 return found;
}
static UIWindow *existingKeyboard(UIWindowScene *scene) {
 UIWindow *known=recentKeyboard;if(known&&!known.hidden&&known.screen==scene.screen)return known;
 Class cls=NSClassFromString(@"UIRemoteKeyboardWindow");
 SEL method=NSSelectorFromString(@"remoteKeyboardWindowForScreen:create:");
 if([cls respondsToSelector:method]){
  id w=((id(*)(id,SEL,UIScreen *,BOOL))objc_msgSend)(cls,method,scene.screen,NO);
  if([w isKindOfClass:UIWindow.class])return w;
 }
 return nil;
}
static BOOL physicalFrame(CGRect raw,UIScreen *screen) {
 double scale=screen.nativeScale;if(scale<=0)return NO;
 return STHPhysicalFrame(raw.origin.x,raw.origin.y,raw.size.width,raw.size.height,
                        screen.nativeBounds.size.width/scale,screen.nativeBounds.size.height/scale);
}

// ALL callers of this function receive SCENE coordinates and SCENE inset.
// A target popup/key UIWindow is used only to measure a fallback host, never
// to redefine the scene's height or add its origin to a scene-level API.
BOOL STHResolveKeyboardScene(UIWindowScene *scene,UIWindow *keyboard,CGRect physical,BOOL ignoreX,CGRect *frame,double *inset) {
 if(!STHFloatingKeyboardScope(scene))return NO;
 if(STHLayoutStatus(NSBundle.mainBundle.bundleIdentifier)!=1)return NO;
 CGRect bounds=scene.coordinateSpace.bounds,raw=CGRectNull;
 double ignored=0;
 if(STHReadLayout(NSBundle.mainBundle.bundleIdentifier,bounds,&raw,&ignored)){
  resolutionSource=@"host-scene";
 }else{
  if(!keyboard)keyboard=existingKeyboard(scene);
  if(keyboard)recentKeyboard=keyboard;
  UIWindow *target=STHTargetKeyboardWindow(scene,keyboard);if(!target)return NO;
  CGRect local=CGRectNull;
  if(keyboard&&!keyboard.hidden&&keyboard.alpha>.01){int budget=512;actualHost(keyboard,target,0,&budget,&local);}
  if(!CGRectIsNull(local)){
   raw=[scene.coordinateSpace convertRect:local fromCoordinateSpace:target];
   resolutionSource=@"host-view-to-scene";
  }else{
   if(CGRectIsNull(physical)){
    if(!session.hasPhysicalFrame||CACurrentMediaTime()-session.physicalAt>1.5)return NO;
    physical=cgRect(session.physicalFrame);
   }
   if(!physicalFrame(physical,target.screen))return NO;
   raw=[scene.coordinateSpace convertRect:physical fromCoordinateSpace:target.screen.fixedCoordinateSpace];
   resolutionSource=@"physical-to-scene";
  }
 }
 if(!isfinite(raw.origin.x)||!isfinite(raw.origin.y)||!isfinite(raw.size.width)||!isfinite(raw.size.height))return NO;
 if(ignoreX){raw.origin.x=bounds.origin.x;raw.size.width=bounds.size.width;}
 CGRect result=canonical(bounds,raw);
 if(frame)*frame=result;if(inset)*inset=result.size.height;
 return YES;
}

static void decision(UIWindowScene *scene,CGRect frame,double inset) {
 static CFTimeInterval last=0;CFTimeInterval now=CACurrentMediaTime();
 STHReportNotificationFrame(NSBundle.mainBundle.bundleIdentifier,scene.coordinateSpace.bounds,frame);
 STHReportLayout(NSBundle.mainBundle.bundleIdentifier,inset,YES);
 if(now-last<.25)return;last=now;
 STHWriteLayoutLog([NSString stringWithFormat:@"decision source=%@ scene=%@ end=%@ inset=%.3f (computed, not measured editor)",
   resolutionSource,NSStringFromCGRect(scene.coordinateSpace.bounds),NSStringFromCGRect(frame),inset]);
}
static BOOL resolveScene(CGRect physical,UIWindowScene **found,CGRect *frame,double *inset) {
 for(UIScene *s in UIApplication.sharedApplication.connectedScenes){
  if(![s isKindOfClass:UIWindowScene.class])continue;
  UIWindowScene *scene=(UIWindowScene *)s;
  if(STHResolveKeyboardScene(scene,nil,physical,NO,frame,inset)){
   if(found)*found=scene;return YES;
  }
 }
 return NO;
}
static NSDictionary *frameInfo(NSDictionary *metadata,CGRect begin,CGRect end) {
 NSMutableDictionary *info=metadata?[metadata mutableCopy]:[NSMutableDictionary new];
 info[UIKeyboardFrameBeginUserInfoKey]=[NSValue valueWithCGRect:begin];
 info[UIKeyboardFrameEndUserInfoKey]=[NSValue valueWithCGRect:end];
 if(info[@"UIKeyboardBoundsUserInfoKey"])
  info[@"UIKeyboardBoundsUserInfoKey"]=[NSValue valueWithCGRect:CGRectMake(0,0,end.size.width,end.size.height)];
 return [info copy];
}

static NSDictionary *normalizedInfo(NSNotification *note,SEL selector) {
 NSDictionary *raw=originalInfo(note,selector);
 // Self-generated frames are already canonical. Never put them in the physical cache.
 if(objc_getAssociatedObject(note,&normalizedKey)||converting||![NSThread isMainThread]||![raw isKindOfClass:NSDictionary.class])return raw;
 NSDictionary *cached=objc_getAssociatedObject(note,&cachedInfoKey);if(cached)return cached;
 NSString *name=note.name;
 BOOL hide=[name isEqualToString:UIKeyboardWillHideNotification]||[name isEqualToString:UIKeyboardDidHideNotification];
 BOOL show=[name isEqualToString:UIKeyboardWillShowNotification]||[name isEqualToString:UIKeyboardDidShowNotification];
 BOOL change=[name isEqualToString:UIKeyboardWillChangeFrameNotification]||[name isEqualToString:UIKeyboardDidChangeFrameNotification];
 if(!show&&!change&&!hide)return raw;
 id v=raw[UIKeyboardFrameEndUserInfoKey];if(![v isKindOfClass:NSValue.class])return raw;
 converting=YES;NSDictionary *result=raw;
 @try{
  CGRect incoming=[v CGRectValue],end=CGRectNull;
  UIWindowScene *scene=nil;double inset=0;
  if(hide){
   scene=sessionScene?:lastHideScene;
   if(scene){
    lastHideScene=scene;
    CGRect b=scene.coordinateSpace.bounds;
    end=CGRectMake(b.origin.x,CGRectGetMaxY(b),b.size.width,0);
   }
  }else resolveScene(incoming,&scene,&end,&inset);
  if(scene&&!CGRectIsNull(end)){
   // Preserve the original animation metadata for app input bars.
   if([raw[UIKeyboardAnimationDurationUserInfoKey] isKindOfClass:NSNumber.class])originalDuration=raw[UIKeyboardAnimationDurationUserInfoKey];
   if([raw[UIKeyboardAnimationCurveUserInfoKey] isKindOfClass:NSNumber.class])originalCurve=raw[UIKeyboardAnimationCurveUserInfoKey];
   CGRect begin=session.hasSceneFrame&&sessionScene==scene?cgRect(session.sceneFrame):end;
   if(!session.hasSceneFrame&&!hide)begin.origin.y=CGRectGetMaxY(scene.coordinateSpace.bounds);
   if(!hide){
    STHSessionPhysical(&session,rectValue(incoming),CACurrentMediaTime(),false,physicalFrame(incoming,scene.screen));
    session.visible=YES;lastRealMetadata=raw;sessionScene=scene;lastHideScene=nil;
   }
   STHSessionCommit(&session,rectValue(end));
   result=frameInfo(raw,begin,end);
   objc_setAssociatedObject(note,&cachedInfoKey,result,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
   decision(scene,end,inset);
  }
  if(hide){STHSessionHide(&session);sessionScene=nil;lastRealMetadata=nil;recentKeyboard=nil;}
 }@catch(NSException *e){result=raw;}
 converting=NO;return result;
}

#include "KeyboardDelivery.inc"

static BOOL refreshQueued;
static void refreshHostedLayout(void) {
 if(postingLayoutRefresh||![NSThread isMainThread])return;
 int phase=STHLayoutStatus(NSBundle.mainBundle.bundleIdentifier);
 if(phase==1&&heldNotes.count)flushHeld(YES);
 if(phase==0){
  discardHeld();heldSession=NO;
  STHSessionHide(&session);sessionScene=nil;lastRealMetadata=nil;return;
 }
 if(phase==2||!session.visible)return;
 CGRect end;UIWindowScene *scene=nil;double inset=0;
 if(!resolveScene(CGRectNull,&scene,&end,&inset)){
  // Host has invalidated or stopped. Do not reuse its old app/physical snapshots.
  if(sessionScene){CGRect mapped;double amount=0;
   if(!STHReadLayout(NSBundle.mainBundle.bundleIdentifier,sessionScene.coordinateSpace.bounds,&mapped,&amount)){
    STHSessionHide(&session);sessionScene=nil;lastRealMetadata=nil;
   }
  }
  return;
 }
 if(sessionScene!=scene){session.hasSceneFrame=false;sessionScene=scene;}
 if(!STHSessionNeedsDelivery(&session,rectValue(end)))return;
 CGRect begin=session.hasSceneFrame?cgRect(session.sceneFrame):end;
 // Commit BEFORE posting; neither idempotence nor hide depends on userInfo reads.
 STHSessionCommit(&session,rectValue(end));
 NSMutableDictionary *metadata=lastRealMetadata?[lastRealMetadata mutableCopy]:[NSMutableDictionary new];
 metadata[UIKeyboardAnimationDurationUserInfoKey]=originalDuration?:@0.25;
 metadata[UIKeyboardAnimationCurveUserInfoKey]=originalCurve?:@7;
 metadata[UIKeyboardIsLocalUserInfoKey]=@YES;
 NSDictionary *info=frameInfo(metadata,begin,end);
 postingLayoutRefresh=YES;
 @try{
  for(NSString *name in @[UIKeyboardWillChangeFrameNotification,UIKeyboardDidChangeFrameNotification]){
   NSNotification *note=[NSNotification notificationWithName:name object:nil userInfo:info];
   objc_setAssociatedObject(note,&normalizedKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
   [NSNotificationCenter.defaultCenter postNotification:note];
  }
  // Invalidate layout so a UIKit-only input client re-queries the SAME scene inset.
  UIWindow *target=STHTargetKeyboardWindow(scene,nil);
  [target setNeedsLayout];[target.rootViewController.view setNeedsLayout];
  decision(scene,end,inset);
 }@catch(NSException *e){}
 postingLayoutRefresh=NO;
}
void STHInstallKeyboardNotifications(void) {
 Class concrete=object_getClass([NSNotification notificationWithName:@"stheno.layout.probe" object:nil userInfo:@{}]);
 Method m=class_getInstanceMethod(concrete,@selector(userInfo));if(!m)return;
 IMP old=method_getImplementation(m);if(old==(IMP)normalizedInfo)return;
 originalInfo=(void *)old;method_setImplementation(m,(IMP)normalizedInfo);
 installDelivery();
 STHObserveLayout(NSBundle.mainBundle.bundleIdentifier,^{
  if(refreshQueued)return;refreshQueued=YES;
  dispatch_async(dispatch_get_main_queue(),^{refreshQueued=NO;refreshHostedLayout();});
 });
 STHWriteLayoutLog(@"2.0.9 app adapter: delivery-frozen scene frame; deferred unstable start");
}
