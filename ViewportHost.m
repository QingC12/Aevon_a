// One card geometry authority. Original keyboard avoidance is not called.
#if !defined(STH_VIEWPORT_HOST_TEST)
#import <UIKit/UIKit.h>
#else
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#endif
#import "ViewportHost.h"
#import "ViewportBus.h"
#import "ViewportDiagnostics.h"
extern void *STHDockCopyFloating(void);
extern size_t STHChooserManagersCount(void *);
extern void *STHChooserCopyManagerAt(size_t,void *);
extern void STHChooserReleaseArray(void *),STHChooserReleaseSwift(void *);
extern void *STHSystemCopyModelIdentifier(void *);
extern BOOL STHNativeMinimized(void *);
extern NSUInteger STHNativeOrientation(void *);
extern CGRect STHNativeRect(void *);
extern double STHNativeGetScale(void *);
extern CGSize STHNativeGetOffset(void *);
extern void STHNativeSetViewportGeometry(void *,const double *);
extern void STHNativeRefreshGeometry(void *);
extern void STHCenterRunAnimation(void (^block)(void),int);
extern void STHGestureInputFocusChanged(void *);
extern BOOL STHSystemActionsEnabled(void);
extern BOOL STHSystemActionRuntimeReady(void);

static __weak id viewportOwner;
static NSString *ownerBundle;
static STHVRect originalCard,currentTarget,physicalKeyboard;
static double originalGeometry[3],writtenGeometry[3],lastOwnerAt;
static BOOL hasWrittenGeometry,localInput,manualOverride;
static BOOL physicallyHidden;
static uint64_t hiddenOwnerKey,hiddenRequestEvent,localBarrierKey,localBarrierEvent;
static STHVRect ownerKeyboard;
static NSSet<NSString *> *publishedBundles;
static BOOL processing;
static NSMutableDictionary<NSString *,NSDictionary *> *lastProbes;
static void recordProbe(NSString *bundle){
 STHVRect a={0},p={0};if(!STHVReadProbe(bundle,&a,&p))return;
 NSDictionary *values=@{@"responderScene":STHVRectJSON(a),@"parentScene":STHVRectJSON(p)};
 if(!lastProbes)lastProbes=[NSMutableDictionary new];
 if([lastProbes[bundle] isEqual:values])return;
 lastProbes[bundle]=values;STHVLog(@"app-geometry-probe",bundle,values);
}
static STHVRect vr(CGRect r){return (STHVRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
static CGRect cr(STHVRect r){return CGRectMake(r.x,r.y,r.w,r.h);}
static STHVRect viewportScreen(void){
#if defined(STH_VIEWPORT_HOST_TEST)
 return (STHVRect){0,0,400,850};
#else
 return vr(UIScreen.mainScreen.fixedCoordinateSpace.bounds);
#endif
}
static double hostNow(void){
#if defined(STH_VIEWPORT_HOST_TEST)
 extern double STHVHostTestNow(void);return STHVHostTestNow();
#else
 return NSProcessInfo.processInfo.systemUptime;
#endif
}
static NSString *modelBundle(void *model){return CFBridgingRelease(STHSystemCopyModelIdentifier(model));}
static void writeCard(void *model,const double geometry[3],BOOL nativeTransaction){
 if(nativeTransaction){STHNativeSetViewportGeometry(model,geometry);STHNativeRefreshGeometry(model);}
 else{
  double s=geometry[0],x=geometry[1],y=geometry[2];
  STHCenterRunAnimation(^{double target[3]={s,x,y};STHNativeSetViewportGeometry(model,target);STHNativeRefreshGeometry(model);},0);
 }
}
static void restoreOwner(BOOL nativeTransaction,NSString *reason){
 id model=viewportOwner;NSString *bundle=ownerBundle;
 viewportOwner=nil;ownerBundle=nil;
 if(model&&hasWrittenGeometry&&!manualOverride){
  double s=STHNativeGetScale((__bridge void *)model);CGSize p=STHNativeGetOffset((__bridge void *)model);
  double g[3]={s,p.width,p.height};
  if(fabs(s-writtenGeometry[0])<.001)g[0]=originalGeometry[0];
  if(hypot(p.width-writtenGeometry[1],p.height-writtenGeometry[2])<.5){g[1]=originalGeometry[1];g[2]=originalGeometry[2];}
  writeCard((__bridge void *)model,g,nativeTransaction);
  STHVPublishLayout(bundle,NO,vr(STHNativeRect((__bridge void *)model)),(STHVRect){0});
  STHVLog(@"host-restore",bundle,@{@"reason":reason,@"card":STHVRectJSON(vr(STHNativeRect((__bridge void *)model)))});
 }
 if(model&&manualOverride){STHNativeRefreshGeometry((__bridge void *)model);STHVPublishLayout(bundle,NO,vr(STHNativeRect((__bridge void *)model)),(STHVRect){0});}
 hasWrittenGeometry=NO;manualOverride=NO;currentTarget=(STHVRect){0};
}
static void applyOwner(void *pointer,NSString *bundle,STHVRect keyboard,uint64_t event,BOOL nativeTransaction){
 id model=(__bridge id)pointer;
 if(localBarrierKey==STHVKey(bundle)&&event<=localBarrierEvent)return;
 if(physicallyHidden&&hiddenOwnerKey==STHVKey(bundle)&&event<=hiddenRequestEvent)return;
 if(localInput||STHNativeMinimized(pointer)||STHNativeOrientation(pointer)!=1)return;
 STHVRect screen=viewportScreen();if(!STHVKeyboard(keyboard,screen))return;
 if(viewportOwner!=model){
  restoreOwner(nativeTransaction,@"handoff");
  STHNativeRefreshGeometry(pointer);originalCard=vr(STHNativeRect(pointer));
  if(!STHVValid(originalCard)||originalCard.w<80||originalCard.h<80)return;
  originalGeometry[0]=STHNativeGetScale(pointer);CGSize p=STHNativeGetOffset(pointer);
  originalGeometry[1]=p.width;originalGeometry[2]=p.height;
  if(!isfinite(originalGeometry[0])||originalGeometry[0]<=0)return;
  viewportOwner=model;ownerBundle=bundle;hasWrittenGeometry=NO;manualOverride=NO;
  STHGestureInputFocusChanged(pointer);
 }
 lastOwnerAt=hostNow();physicalKeyboard=keyboard;ownerKeyboard=keyboard;physicallyHidden=NO;
 if(hasWrittenGeometry&&!manualOverride){
  double scale=STHNativeGetScale(pointer);CGSize p=STHNativeGetOffset(pointer);
  if(fabs(scale-writtenGeometry[0])>.001||hypot(p.width-writtenGeometry[1],p.height-writtenGeometry[2])>.5)manualOverride=YES;
 }
 if(manualOverride){
  STHNativeRefreshGeometry(pointer);currentTarget=vr(STHNativeRect(pointer));
  STHVPublishLayout(bundle,YES,currentTarget,keyboard);return;
 }
 STHVRect target=STHVTarget(originalCard,screen,keyboard);
 if(!STHVValid(target))return;
 if(!hasWrittenGeometry||!STHVNear(target,currentTarget,.5)){
  double factor=target.w/originalCard.w;
  double g[3]={originalGeometry[0]*factor,
   originalGeometry[1]+target.x+target.w/2-(originalCard.x+originalCard.w/2),
   originalGeometry[2]+target.y+target.h/2-(originalCard.y+originalCard.h/2)};
  // Publish the identical mathematical target used by the application bridge.
  // Native keyboard delivery owns this transaction; an IPC wake uses the same
  // original withAnimation ABI only when that transaction is not on this stack.
  STHVPublishLayout(bundle,YES,target,keyboard);
  writeCard(pointer,g,nativeTransaction);
  for(int i=0;i<3;i++)writtenGeometry[i]=g[i];
  hasWrittenGeometry=YES;currentTarget=target;
  STHVLog(@"host-target",bundle,@{@"nativeTransaction":@(nativeTransaction),@"before":STHVRectJSON(originalCard),@"target":STHVRectJSON(target),@"measured":STHVRectJSON(vr(STHNativeRect(pointer))),@"physicalKeyboard":STHVRectJSON(keyboard)});
 }else STHVPublishLayout(bundle,YES,currentTarget,keyboard);
}
static void maintainOwner(BOOL nativeTransaction){
 if(!viewportOwner)return;
 STHVSnapshot ended={0};uint64_t key=STHVRequestOwner();BOOL known=STHVReadRequest(ownerBundle,&ended);
 if(known&&!ended.active)restoreOwner(nativeTransaction,@"explicit-input-end");
 else if(key&&key!=STHVKey(ownerBundle))restoreOwner(nativeTransaction,@"external-owner");
 else if(known&&ended.active&&key==STHVKey(ownerBundle))lastOwnerAt=hostNow();
 else if(hostNow()-lastOwnerAt>3.5)restoreOwner(nativeTransaction,@"owner-expired");
}
static void updateRegistry(BOOL nativeTransaction){
 if(processing||!NSThread.isMainThread||!STHSystemActionRuntimeReady())return;processing=YES;
 if(!STHSystemActionsEnabled()){
  restoreOwner(nativeTransaction,@"disabled");
  for(NSString *bundle in publishedBundles)STHVPublishLayout(bundle,NO,(STHVRect){0},(STHVRect){0});
  publishedBundles=nil;processing=NO;return;
 }
 maintainOwner(nativeTransaction);
 void *array=STHDockCopyFloating();if(!array){processing=NO;return;}
 NSMutableSet *current=[NSMutableSet new];
 uint64_t key=STHVRequestOwner();
 @try{
  size_t count=STHChooserManagersCount(array);if(count>4096)return;
  for(size_t i=0;i<count;i++){
   void *pointer=STHChooserCopyManagerAt(i,array);if(!pointer)continue;
   @try{
    NSString *bundle=modelBundle(pointer);if(!bundle.length||[current containsObject:bundle])continue;
    BOOL minimized=STHNativeMinimized(pointer);
    if(minimized){if(viewportOwner==(__bridge id)pointer)restoreOwner(nativeTransaction,@"minimized");continue;}
    [current addObject:bundle];recordProbe(bundle);STHVSnapshot request={0};
    if(key==STHVKey(bundle)&&STHVReadRequest(bundle,&request)){
     if(request.active&&STHSystemActionsEnabled()&&!localInput){
      STHVRect keys=STHVKeyboard(request.keyboard,viewportScreen())?request.keyboard:physicalKeyboard;
      applyOwner(pointer,bundle,keys,request.event,nativeTransaction);
     }else if(viewportOwner==(__bridge id)pointer)restoreOwner(nativeTransaction,@"input-ended");
    }
    if(viewportOwner==(__bridge id)pointer&&hasWrittenGeometry){
     STHVPublishLayout(bundle,YES,currentTarget,ownerKeyboard);
    }else{
     STHNativeRefreshGeometry(pointer);STHVRect card=vr(STHNativeRect(pointer));
     if(STHVValid(card))STHVPublishLayout(bundle,NO,card,(STHVRect){0});
    }
   }@finally{STHChooserReleaseSwift(pointer);}
  }
  if(viewportOwner&&(![current containsObject:ownerBundle]||!STHSystemActionsEnabled()))restoreOwner(nativeTransaction,@"removed-or-disabled");
  // Unavailable reads never change geometry; maintainOwner bounds actual loss.
  for(NSString *bundle in publishedBundles)if(![current containsObject:bundle])STHVPublishLayout(bundle,NO,(STHVRect){0},(STHVRect){0});
  publishedBundles=[current copy];
 }@finally{STHChooserReleaseArray(array);processing=NO;}
}
void STHViewportSetLocalInput(BOOL active){
 if(!NSThread.isMainThread)return;localInput=active;
 if(active){
  localBarrierKey=STHVRequestOwner();localBarrierEvent=0;
  for(NSString *bundle in publishedBundles)if(STHVKey(bundle)==localBarrierKey){STHVSnapshot request={0};if(STHVReadRequest(bundle,&request))localBarrierEvent=request.event;break;}
  restoreOwner(NO,@"local-input");
 }
}
void STHViewportModelMinimized(void *model){
 if(NSThread.isMainThread&&viewportOwner==(__bridge id)model)restoreOwner(YES,@"dock");
}
void STHViewportModelChanged(void *model){if(NSThread.isMainThread)updateRegistry(NO);}
BOOL STHViewportKeyboardExcludes(CGPoint point){
 return STHVKeyboard(physicalKeyboard,viewportScreen())&&CGRectContainsPoint(cr(physicalKeyboard),point);
}
void STHViewportPhysicalWill(CGRect frame,BOOL hiding){
 if(!NSThread.isMainThread)return;
 if(hiding){
  hiddenOwnerKey=STHVRequestOwner();hiddenRequestEvent=0;
  STHVSnapshot last={0};if(ownerBundle&&STHVReadRequest(ownerBundle,&last)&&last.owner==hiddenOwnerKey)hiddenRequestEvent=last.event;
  physicallyHidden=YES;physicalKeyboard=(STHVRect){0};
 }else if(STHVKeyboard(vr(frame),viewportScreen())){physicallyHidden=NO;physicalKeyboard=vr(frame);}
 // This entry is invoked only inside the unmodified original animation ABI.
 updateRegistry(YES);
}
#if !defined(STH_VIEWPORT_HOST_TEST)
__attribute__((constructor)) static void installViewportHost(void){dispatch_async(dispatch_get_main_queue(),^{
 if(!STHSystemActionRuntimeReady()){STHVLog(@"host-core-not-ready",@"com.apple.springboard",nil);return;}
 STHVObserveRequests(^{STHCenterRunAnimation(^{updateRegistry(YES);},0);});
 for(NSString *name in @[UIKeyboardWillShowNotification,UIKeyboardWillChangeFrameNotification,UIKeyboardWillHideNotification]){
  [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
   BOOL hide=[note.name isEqualToString:UIKeyboardWillHideNotification];
   id value=note.userInfo[UIKeyboardFrameEndUserInfoKey];
   if([note.object isKindOfClass:UIScreen.class]&&note.object!=UIScreen.mainScreen)return;
   CGRect frame=[value isKindOfClass:NSValue.class]?[value CGRectValue]:CGRectNull;
   if(!CGRectIsNull(frame))frame=[UIScreen.mainScreen.coordinateSpace convertRect:frame toCoordinateSpace:UIScreen.mainScreen.fixedCoordinateSpace];
   BOOL noDockedKeyboard=hide||!STHVKeyboard(vr(frame),viewportScreen());
   STHCenterRunAnimation(^{STHViewportPhysicalWill(frame,noDockedKeyboard);},0);
  }];
 }
 static dispatch_source_t registryTimer;registryTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
 dispatch_source_set_timer(registryTimer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/2),NSEC_PER_SEC,NSEC_PER_SEC/10);
 dispatch_source_set_event_handler(registryTimer,^{updateRegistry(NO);});dispatch_resume(registryTimer);
 STHVLog(@"host-start",@"com.apple.springboard",@{@"architecture":@"viewport31",@"legacyAvoidanceCalled":@NO});
});}
#endif
