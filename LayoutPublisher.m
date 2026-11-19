// Publish committed geometry, never each intermediate native notification.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import "LayoutBus.h"
#import "LayoutSettle.h"
extern NSString *STHNativeCopyBundleID(void *) NS_RETURNS_RETAINED;
extern CGRect STHNativeRect(void *);
extern NSUInteger STHNativeOrientation(void *);
extern void STHNativeRefreshGeometry(void *);
static __weak id observedModel;
static NSString *observedBundle;
static CGRect keyboardFrame;
static CFTimeInterval keyboardFrameAt,lastHeartbeat;
static dispatch_source_t timer;
static id changeObserver,doneObserver;
static STHLayoutSettle settling;
static NSString *source;
static BOOL applying;
static __weak id preparedModel;
static NSString *preparedBundle;
static unsigned prepareGeneration;
void STHPrepareLayoutFocus(void *model){
 if(![NSThread isMainThread]||!model)return;
 if(observedModel==(__bridge id)model&&settling.active)return;
 NSString *bundle=STHNativeCopyBundleID(model);if(!bundle.length)return;
 if(preparedBundle&&![preparedBundle isEqualToString:bundle])STHPublishLayout(preparedBundle,CGRectZero,CGRectZero,NO);
 preparedModel=(__bridge id)model;preparedBundle=bundle;
 CGRect current=STHNativeRect(model),screen=UIScreen.mainScreen.bounds;
 if(current.size.width>1&&current.size.height>1){
  double factor=screen.size.width/current.size.width;
  CGRect target=CGRectMake(screen.origin.x,CGRectGetMidY(current)-current.size.height*factor*.5,
                           screen.size.width,current.size.height*factor);
  STHPreviewLayout(bundle,target);
 }else STHBeginLayout(bundle);
 unsigned generation=++prepareGeneration;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,650*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
  if(generation!=prepareGeneration)return;
  if(!settling.active||![observedBundle isEqualToString:bundle])STHPublishLayout(bundle,CGRectZero,CGRectZero,NO);
  preparedModel=nil;preparedBundle=nil;
 });
}
static STHRect rr(CGRect r){return (STHRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
static CGRect cg(STHRect r){return CGRectMake(r.x,r.y,r.w,r.h);}
static BOOL usable(CGRect r,CGRect screen){return STHFiniteRect(rr(r))&&r.size.width>=screen.size.width*.7&&
 r.size.height>=60&&r.size.height<screen.size.height*.7&&fabs(CGRectGetMaxY(r)-CGRectGetMaxY(screen))<=10;}
static BOOL collect(UIView *v,UIScreen *screen,int depth,int *budget,CGRect *best){
 if(!v||v.hidden||v.alpha<.01||depth>14||--*budget<0)return NO;
 NSString *name=NSStringFromClass(v.class);BOOL found=NO;
 if([name containsString:@"InputSetHost"]||[name containsString:@"RemoteKeyboardPlaceholder"]||[name containsString:@"InputSetContainer"]){
  CGRect r=[v convertRect:v.bounds toCoordinateSpace:screen.fixedCoordinateSpace];
  if(usable(r,screen.bounds)){*best=CGRectIsNull(*best)?r:CGRectUnion(*best,r);found=YES;}
 }
 for(UIView *c in v.subviews){if(*budget<=0)break;found=collect(c,screen,depth+1,budget,best)||found;}
 return found;
}
static void accessories(UIView *v,UIScreen *s,int depth,int *budget,CGRect *assembly){
 if(!v||v.hidden||v.alpha<.01||depth>14||--*budget<0)return;
 NSString *n=NSStringFromClass(v.class).lowercaseString;
 if([n containsString:@"accessory"]||[n containsString:@"assistant"]||[n containsString:@"candidate"]||[n containsString:@"prediction"]||[n containsString:@"toolbar"]){
  CGRect r=[v convertRect:v.bounds toCoordinateSpace:s.fixedCoordinateSpace];
  if(r.size.width>=s.bounds.size.width*.7&&r.size.height>=10&&r.size.height<=160&&r.origin.y>=0&&
    r.origin.y<=assembly->origin.y&&fabs(CGRectGetMaxY(r)-CGRectGetMinY(*assembly))<=8)*assembly=CGRectUnion(*assembly,r);
 }
 for(UIView *c in v.subviews){if(*budget<=0)break;accessories(c,s,depth+1,budget,assembly);}
}
static CGRect physicalKeys(void){
 UIScreen *s=UIScreen.mainScreen;NSMutableArray<UIWindow *> *windows=[NSMutableArray new];
 Class cls=NSClassFromString(@"UIRemoteKeyboardWindow");SEL sel=NSSelectorFromString(@"remoteKeyboardWindowForScreen:create:");
 if([cls respondsToSelector:sel]){id w=((id(*)(id,SEL,UIScreen *,BOOL))objc_msgSend)(cls,sel,s,NO);if([w isKindOfClass:UIWindow.class])[windows addObject:w];}
 // remoteKeyboardWindowForScreen may return nil in SpringBoard. Inspect only
 // its own visible keyboard windows; never a scene content view or typed data.
 for(UIWindow *w in UIApplication.sharedApplication.windows)
  if(!w.hidden&&[NSStringFromClass(w.class) containsString:@"Keyboard"]&&![windows containsObject:w])[windows addObject:w];
 for(UIWindow *w in windows){
  if(w.hidden||w.alpha<.01)continue;
  int budget=512;CGRect r=CGRectNull;
  if(collect(w,s,0,&budget,&r)){
   for(int pass=0;pass<3;pass++)for(UIWindow *part in windows){int b=512;accessories(part,s,0,&b,&r);}
   source=@"visible-assembly";return r;
  }
 }
 source=@"native-notification-settled";return keyboardFrame;
}
static void tick(void){
 id strong=observedModel;if(!strong||!observedBundle||applying||!settling.active)return;
 void *m=(__bridge void *)strong;if(STHNativeOrientation(m)!=1)return;
 STHNativeRefreshGeometry(m);
 CGRect card=STHNativeRect(m),keys=physicalKeys();double now=CACurrentMediaTime();
 if(!usable(keys,UIScreen.mainScreen.bounds))return;
 BOOL commit=STHSettleSample(&settling,rr(card),rr(keys),now);
 if(commit){
  // Do not replay native keyboard-show after its animation already started:
  // that replay generated a second75pt/342pt cycle in the2.0.9 log.
  // Native avoidance, movement and their original spring continue unmodified.
  settling.committedCard=rr(card);settling.candidateCard=rr(card);
  BOOL ok=STHPublishLayout(observedBundle,card,keys,YES);lastHeartbeat=now;
  STHWriteLayoutLog([NSString stringWithFormat:@"stable-commit session=%u bundle=%@ card=%@ keyboard=%@ source=%@ native=%@ nativeAge=%.3f transport=%@",
    settling.generation,observedBundle,NSStringFromCGRect(card),NSStringFromCGRect(keys),source,NSStringFromCGRect(keyboardFrame),now-keyboardFrameAt,ok?@"ok":@"failed"]);
 }else if(settling.haveCommitted&&now-lastHeartbeat>=.4){
  // Heartbeat the committed pair, NOT the pending oscillating pair. No changed
  // notification, no transient zero commit and no app re-layout every100ms.
  STHPublishLayout(observedBundle,cg(settling.committedCard),cg(settling.committedKeys),YES);lastHeartbeat=now;
 }
}
void STHStartLayout(void *model,CGRect keyboard){
 if(![NSThread isMainThread]||!model)return;
 NSString *bundle=STHNativeCopyBundleID(model);if(![bundle isKindOfClass:NSString.class]||bundle.length==0)return;
 BOOL same=observedModel==(__bridge id)model&&[observedBundle isEqualToString:bundle]&&settling.active;
 if(!same){
  if(observedBundle)STHPublishLayout(observedBundle,CGRectZero,CGRectZero,NO);
  observedModel=(__bridge id)model;observedBundle=bundle;
  keyboardFrame=CGRectNull;keyboardFrameAt=0;lastHeartbeat=0;source=@"new-session-awaiting-frame";
  STHSettleBegin(&settling,CACurrentMediaTime());STHBeginLayout(bundle);
  STHWriteLayoutLog([NSString stringWithFormat:@"session-begin %u bundle=%@ (awaiting stable final card)",settling.generation,bundle]);
 }
 if(usable(keyboard,UIScreen.mainScreen.bounds)){keyboardFrame=keyboard;keyboardFrameAt=CACurrentMediaTime();}
 if(!timer){timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
  dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC),20*NSEC_PER_MSEC,5*NSEC_PER_MSEC);
  dispatch_source_set_event_handler(timer,^{tick();});dispatch_resume(timer);}
 // Do NOT publish the old pre-expansion card from this entry.
}
void STHUpdateLayout(void){
 if(![NSThread isMainThread])return;
 id m=observedModel;
 if(m&&settling.active&&!settling.haveCommitted){
  // Keyboard.m calls here AFTER setting the full-width target, in the same
  // original WillShow transaction. Publish it immediately, do not wait160ms.
  STHNativeRefreshGeometry((__bridge void *)m);
  CGRect card=STHNativeRect((__bridge void *)m),keys=physicalKeys();
  if(usable(keys,UIScreen.mainScreen.bounds)&&STHFiniteRect(rr(card))&&card.size.width>=40&&card.size.height>=40){
   settling.haveCommitted=YES;settling.committedCard=rr(card);settling.committedKeys=rr(keys);
   STHPublishLayout(observedBundle,card,keys,YES);lastHeartbeat=CACurrentMediaTime();
   STHWriteLayoutLog([NSString stringWithFormat:@"initial-sync session=%u bundle=%@ card=%@ keyboard=%@ source=%@ nativeAge=%.3f (no notification hold)",settling.generation,observedBundle,NSStringFromCGRect(card),NSStringFromCGRect(keys),source,CACurrentMediaTime()-keyboardFrameAt]);
  }
 }
 tick();
}
void STHStopLayout(void){
 prepareGeneration++;
 if(preparedBundle&&![preparedBundle isEqualToString:observedBundle])STHPublishLayout(preparedBundle,CGRectZero,CGRectZero,NO);
 preparedModel=nil;preparedBundle=nil;
 if(timer){dispatch_source_cancel(timer);timer=nil;}
 if(observedBundle){STHPublishLayout(observedBundle,CGRectZero,CGRectZero,NO);
  STHWriteLayoutLog([NSString stringWithFormat:@"session-hide %u bundle=%@",settling.generation,observedBundle]);}
 STHSettleEnd(&settling);observedModel=nil;observedBundle=nil;keyboardFrame=CGRectNull;
 keyboardFrameAt=0;lastHeartbeat=0;source=nil;
}
__attribute__((constructor)) static void ready(void){dispatch_async(dispatch_get_main_queue(),^{
 STHWriteLayoutLog(@"stheno 2.0.11 publisher: session-local initial geometry and editor diagnostics");
 void(^update)(NSNotification *)=^(NSNotification *n){
  if(!observedModel||applying)return;
  id v=n.userInfo[UIKeyboardFrameEndUserInfoKey];if(![v isKindOfClass:NSValue.class])return;
  CGRect r=[v CGRectValue];if(!usable(r,UIScreen.mainScreen.bounds))return;
  if(!STHSameRect(rr(r),rr(keyboardFrame)))STHWriteLayoutLog([NSString stringWithFormat:@"native-candidate session=%u frame=%@ phase=%@ (not yet committed)",settling.generation,NSStringFromCGRect(r),n.name]);
  keyboardFrame=r;keyboardFrameAt=CACurrentMediaTime();tick();
 };
 changeObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardWillChangeFrameNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:update];
 doneObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardDidChangeFrameNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:update];
});}
