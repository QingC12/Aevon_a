// New viewport keyboard client. No editor/view transforms or per-app profiles.
#if defined(STH_VIEWPORT_CLIENT_TEST)
#import "test_viewport_client_support.h"
#else
#import <UIKit/UIKit.h>
#endif
#import <objc/runtime.h>
#import <objc/message.h>
#import "ViewportBus.h"
#import "ViewportAuthority.h"
#import "AppSceneReflow.h"
#import "ViewportProcess.h"
#import "ViewportStartup.h"
#import <mach-o/dyld.h>
#import "ViewportDiagnostics.h"
static __weak UIView *editingView;
static __weak UIWindowScene *editingScene;
static BOOL visible,mappedSession,insideDelivery,predictionPending;
static uint64_t predictionSerial;
static STHVRect physicalFrame,lastSceneFrame;
static CGFloat gapWorst;static NSUInteger gapSamples;
static NSDictionary *realMetadata;
static dispatch_source_t leaseTimer;
static NSUInteger sessionGeneration;
// One keyboard session may need two corrections that the native path never
// makes: the keyboard it was handed may be shorter than the keyboard on screen
// (a trial frame) and a third party input method draws its own tool row where
// the application put its composer. Both are measured, both are bounded.
static CGFloat correctionLift;
static NSUInteger corrections,localizedForeign;
static STHVRect lastFixField;
static void (*systemPost)(id,SEL,NSNotification *);
static void (*systemPostName)(id,SEL,NSString *,id,NSDictionary *);
static CGFloat (*systemInset)(id,SEL,UIWindowScene *,BOOL *,BOOL);
static STHVRect vr(CGRect r){return (STHVRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
static CGRect cr(STHVRect r){return CGRectMake(r.x,r.y,r.w,r.h);}
static NSString *bundle(void){
#if defined(STH_VIEWPORT_CLIENT_TEST)
 return @"test.stheno.viewport32.client";
#else
 return NSBundle.mainBundle.bundleIdentifier;
#endif
}
static BOOL ready(UIView *view){
 UIWindow *w=view.window;UIWindowScene *s=w.windowScene;
 return view&&view.isFirstResponder&&w&&!w.hidden&&w.alpha>.01&&s&&
  s.activationState!=UISceneActivationStateBackground&&s.activationState!=UISceneActivationStateUnattached&&
  ![NSStringFromClass(w.class) containsString:@"Keyboard"];
}
static UIView *findResponder(UIView *view,int depth,int *budget){
 if(!view||view.hidden||view.alpha<.01||depth>18||--*budget<0)return nil;
 if(ready(view))return view;
 for(UIView *child in view.subviews){UIView *found=findResponder(child,depth+1,budget);if(found)return found;}
 return nil;
}
static UIView *responder(void){
 if(ready(editingView))return editingView;
 editingView=nil;
 for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
  if(![scene isKindOfClass:UIWindowScene.class]||scene.activationState==UISceneActivationStateBackground||scene.activationState==UISceneActivationStateUnattached)continue;
  for(UIWindow *window in ((UIWindowScene *)scene).windows){
   if([NSStringFromClass(window.class) containsString:@"Keyboard"])continue;
   int budget=1200;UIView *found=findResponder(window,0,&budget);if(found){editingView=found;return found;}
  }
 }
 return nil;
}
BOOL STHVSceneReflowPolicy(BOOL *enabled){STHVSnapshot host={0};if(!NSThread.isMainThread||!STHVReadLayout(bundle(),&host)||!host.hosted)return NO;if(enabled)*enabled=host.reflowEnabled;return YES;}
BOOL STHVSceneIsHosted(void){
 STHVSnapshot host={0};return NSThread.isMainThread&&STHVReadLayout(bundle(),&host)&&host.hosted&&STHVValid(host.card);
}
static BOOL mapFrame(UIWindowScene *scene,BOOL firstWill,STHVRect *mapped){
 if(!scene||scene.screen!=UIScreen.mainScreen||scene.interfaceOrientation!=UIInterfaceOrientationPortrait)return NO;
 STHVSnapshot host={0};if(!STHVReadLayout(bundle(),&host)||!host.hosted||!STHVValid(host.card))return NO;
 STHVRect screen=vr(STHVUnmodifiedScreenBounds(scene.screen));
 if(STHVClientAuthorityMode(host.hosted,host.card,vr(scene.coordinateSpace.bounds),screen,host.physicalGeneration,host.keyboardVisible)!=STHVClientVisible)return NO;
 if(!STHVAuthoritativeFrame(host.card,host.keyboard,screen,host.physicalGeneration,host.keyboardVisible,NULL))return NO;
 if(firstWill&&!host.active){predictionPending=YES;predictionSerial=host.serial;}
 if(host.active)predictionPending=NO;
 BOOL owns=STHVRequestOwner()==STHVKey(bundle());if(!owns)return NO;
 BOOL predict=predictionPending&&host.serial==predictionSerial&&owns;
 if(!host.active&&!predict)return NO;
 STHVRect card=host.active?host.card:STHVTarget(host.card,screen,host.keyboard);
 if(!STHVAuthoritativeMap(card,host.keyboard,screen,vr(scene.coordinateSpace.bounds),host.physicalGeneration,host.keyboardVisible,mapped))return NO;
 physicalFrame=host.keyboard;visible=YES;return YES;
}
// The physical keyboard mapped into this scene without asking whether this
// bundle currently owns the card. It is a lower bound on the keyboard the
// application must be told about; it never writes card geometry.
static BOOL STHVPhysicalFloor(UIWindowScene *scene,STHVSnapshot *authority,STHVRect *out){
 if(!scene||!authority||!out)return NO;
 if(!authority->hosted||!authority->keyboardVisible)return NO;
 STHVRect screen=vr(STHVUnmodifiedScreenBounds(scene.screen));
 if(!STHVValid(authority->card)||!STHVKeyboard(authority->keyboard,screen))return NO;
 STHVRect mapped={0};
 if(!STHVAuthoritativeMap(authority->card,authority->keyboard,screen,vr(scene.coordinateSpace.bounds),1,true,&mapped))return NO;
 if(!STHVValid(mapped))return NO;
 *out=mapped;return YES;
}
static CGRect notificationFrame(UIWindowScene *scene,STHVRect mapped){
 // Convert the canonical scene frame back to the screen before delivery so an
 // application's own screen->view conversion runs exactly once.
 return [scene.coordinateSpace convertRect:cr(mapped) toCoordinateSpace:scene.screen.coordinateSpace];
}
static NSDictionary *frameInfo(NSDictionary *raw,UIWindowScene *scene,STHVRect begin,STHVRect end){
 NSMutableDictionary *info=raw?[raw mutableCopy]:[NSMutableDictionary new];
 info[UIKeyboardFrameBeginUserInfoKey]=[NSValue valueWithCGRect:notificationFrame(scene,begin)];
 info[UIKeyboardFrameEndUserInfoKey]=[NSValue valueWithCGRect:notificationFrame(scene,end)];
 // Everything this client hands over is a keyboard for this scene, whatever the
 // process that drew it. Observable UIKit locality stays as delivered so an
 // application that gates on it can decide; the flag is only rewritten on the
 // copy that describes our own canonical frame.
 info[UIKeyboardIsLocalUserInfoKey]=@YES;
 if(info[@"UIKeyboardBoundsUserInfoKey"])info[@"UIKeyboardBoundsUserInfoKey"]=[NSValue valueWithCGRect:CGRectMake(0,0,end.w,end.h)];
 return [info copy];
}
static void probe(NSString *event,NSDictionary *extra){
 UIView *view=editingView;UIWindowScene *scene=view.window.windowScene?:editingScene;
 if(!scene)return;
 NSMutableDictionary *data=extra?[extra mutableCopy]:[NSMutableDictionary new];
 data[@"scene"]=STHVRectJSON(vr(scene.coordinateSpace.bounds));
 data[@"physicalKeyboard"]=STHVRectJSON(physicalFrame);
 data[@"mappedScene"]=STHVRectJSON(lastSceneFrame);
 data[@"mapped"]=@(mappedSession);data[@"visible"]=@(visible);
 NSMutableArray *chain=[NSMutableArray new];UIView *part=view;
 for(int i=0;i<6&&part;i++,part=part.superview){
  CGRect r=[part convertRect:part.bounds toCoordinateSpace:scene.coordinateSpace];
  CGAffineTransform t=part.transform;
  [chain addObject:@{@"class":NSStringFromClass(part.class),@"rect":STHVRectJSON(vr(r)),@"hidden":@(part.hidden),@"clipped":@(part.clipsToBounds),@"transform":@[@(t.a),@(t.b),@(t.c),@(t.d),@(t.tx),@(t.ty)]}];
 }
 data[@"ancestors"]=chain;
 if(view){
  STHVRect a=vr([view convertRect:view.bounds toCoordinateSpace:scene.coordinateSpace]);
  UIView *parent=view.superview;STHVRect p=parent?vr([parent convertRect:parent.bounds toCoordinateSpace:scene.coordinateSpace]):a;
  // The one measurement the session is judged by: the bottom edge of the field
  // being edited against the top of the keyboard that was actually delivered.
  // Positive clearance means the field sits clear of the keyboard; negative
  // means it is behind it. Both are geometry only.
  CGFloat clearance=lastSceneFrame.y-(a.y+a.h);
  data[@"inputRect"]=STHVRectJSON(a);
  data[@"inputBottom"]=@(a.y+a.h);
  data[@"keyboardTop"]=@(lastSceneFrame.y);
  data[@"clearance"]=@(clearance);
  if(mappedSession){
   if(!gapSamples++){gapWorst=clearance;}
   else if(clearance<gapWorst)gapWorst=clearance;
   data[@"clearanceWorst"]=@(gapWorst);data[@"clearanceSamples"]=@(gapSamples);
  }
  STHVPublishProbe(bundle(),a,p);
 }
 STHVLog(event,bundle(),data);
}
static void stopLease(void){if(leaseTimer){dispatch_source_cancel(leaseTimer);leaseTimer=nil;}}
static void startLease(void){
 if(leaseTimer)return;
 leaseTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
 dispatch_source_set_timer(leaseTimer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,NSEC_PER_SEC/10);
 dispatch_source_set_event_handler(leaseTimer,^{
  if(!ready(editingView)){stopLease();STHVPublishRequest(bundle(),NO,(STHVRect){0});return;}
  // Renewal never writes the shared owner. A former fullscreen app cannot
  // steal input back from a newly focused floating card through a heartbeat.
  if(!STHVRenewRequest(bundle(),(STHVRect){0})&&!STHVResumeRequest(bundle(),(STHVRect){0})){
   STHVLog(@"client-owner-not-renewed",bundle(),@{@"currentOwner":@(STHVRequestOwner())});
  }
 });dispatch_resume(leaseTimer);
}
static void deliver(NSNotificationCenter *center,NSNotification *note){
 BOOL previous=insideDelivery;insideDelivery=YES;
 @try{systemPost(center,@selector(postNotification:),note);}@finally{insideDelivery=previous;}
}
static BOOL keyboardEvent(NSString *name){
 return [name isEqualToString:UIKeyboardWillShowNotification]||[name isEqualToString:UIKeyboardDidShowNotification]||
  [name isEqualToString:UIKeyboardWillChangeFrameNotification]||[name isEqualToString:UIKeyboardDidChangeFrameNotification]||
  [name isEqualToString:UIKeyboardWillHideNotification]||[name isEqualToString:UIKeyboardDidHideNotification];
}
// Record only, no side effects: the event is refused exactly as before.
static void ignored(NSNotification *note,NSString *reason){
 STHVLog(@"client-ignored",bundle(),@{@"notification":note.name?:@"-",@"reason":reason,@"hasView":@(editingView!=nil),@"visible":@(visible),@"mapped":@(mappedSession),@"scene":STHVRectJSON(lastSceneFrame)});
}
static void reconcile(void);
// One measurement is not enough. An application finishes its own avoidance
// animation a few hundred milliseconds after the last keyboard event, and an
// input method settles its panel in steps, so a session that looked clear at
// 180 ms can end up with the composer under the keys again. The check therefore
// stays armed for a short bounded window and stops as soon as the session ends.
static NSUInteger reconcilePasses;
static void armReconcile(NSUInteger delay){
 if(reconcilePasses>=3)return;
 reconcilePasses++;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)delay*NSEC_PER_MSEC),dispatch_get_main_queue(),^{reconcile();});
}
static void scheduleReconcile(void){
 reconcilePasses=0;
 armReconcile(180);
}
static void resetCorrection(void){
 correctionLift=0;corrections=0;lastFixField=(STHVRect){0};localizedForeign=0;reconcilePasses=0;
}
// The composer is judged by one number: the bottom edge of the field being
// edited against the top of the keyboard that was actually handed over. When
// that number is negative the application laid out for a shorter keyboard than
// the one on screen, which is what a trial frame and an input method tool row
// both produce. The answer is another canonical frame, raised by exactly the
// shortfall, delivered through the same path and with a bounded repeat count.
static void reconcile(void){
 if(!NSThread.isMainThread||!visible||!mappedSession||!ready(editingView))return;
 if(corrections>=3)return;
 UIWindowScene *scene=editingView.window.windowScene?:editingScene;
 if(!scene||scene.screen!=UIScreen.mainScreen)return;
 STHVRect field=vr([editingView convertRect:editingView.bounds toCoordinateSpace:scene.coordinateSpace]);
 if(!STHVValid(field))return;
 CGFloat clearance=lastSceneFrame.y-(field.y+field.h);
 if(clearance>=-0.5){STHVLog(@"client-clearance-ok",bundle(),@{@"clearance":@(clearance),@"corrections":@(corrections),@"pass":@(reconcilePasses),@"field":STHVRectJSON(field),@"keyboardTop":@(lastSceneFrame.y)});armReconcile(260);return;}
 CGFloat shortfall=-clearance+4.0;
 if(STHVNear(field,lastFixField,0.5)){STHVLog(@"client-clearance-stalled",bundle(),@{@"clearance":@(clearance),@"corrections":@(corrections),@"pass":@(reconcilePasses),@"field":STHVRectJSON(field)});return;}
 STHVRect bounds=vr(scene.coordinateSpace.bounds);
 CGFloat top=lastSceneFrame.y-shortfall;
 if(!isfinite(top)||top<bounds.y)return;
 STHVRect end={lastSceneFrame.x,top,lastSceneFrame.w,(bounds.y+bounds.h)-top};
 if(!STHVValid(end))return;
 STHVRect before=lastSceneFrame;
 corrections++;lastFixField=field;correctionLift+=shortfall;
 NSMutableDictionary *metadata=realMetadata?[realMetadata mutableCopy]:[NSMutableDictionary new];
 metadata[UIKeyboardAnimationDurationUserInfoKey]=@0;
 metadata[UIKeyboardAnimationCurveUserInfoKey]=@0;
 metadata[UIKeyboardIsLocalUserInfoKey]=@YES;
 NSDictionary *info=frameInfo(metadata,scene,lastSceneFrame,end);
 lastSceneFrame=end;mappedSession=YES;
 for(NSString *name in @[UIKeyboardWillChangeFrameNotification,UIKeyboardDidChangeFrameNotification])
  deliver(NSNotificationCenter.defaultCenter,[NSNotification notificationWithName:name object:scene.screen userInfo:info]);
 STHVLog(@"client-clearance-fix",bundle(),@{@"before":STHVRectJSON(before),@"after":STHVRectJSON(end),@"clearance":@(clearance),@"shortfall":@(shortfall),@"field":STHVRectJSON(field),@"corrections":@(corrections),@"correctionLift":@(correctionLift)});
 armReconcile(260);
}
static BOOL intercept(NSNotificationCenter *center,NSNotification *note){
 if(insideDelivery||center!=NSNotificationCenter.defaultCenter||!NSThread.isMainThread||!keyboardEvent(note.name))return NO;
 // A refused event used to disappear without a trace, which is why a session
 // could show a keyboard on screen and not one line about it. The reason is now
 // recorded and the refusal itself is unchanged.
 NSDictionary *raw=note.userInfo;
 if(![raw isKindOfClass:NSDictionary.class]){ignored(note,@"no-user-info");return NO;}
 // A docked keyboard drawn by another process is still the keyboard on this
 // screen. Refusing it whole is what the third party input method case was
 // diagnosed as: the application never hears about the keyboard, keeps its
 // composer where it was and the keys cover it. Locality is recorded, then the
 // same event is delivered with the flag corrected further down.
 id locality=raw[UIKeyboardIsLocalUserInfoKey];
 BOOL foreign=[locality isKindOfClass:NSNumber.class]&&![(NSNumber *)locality boolValue];
 BOOL hide=[note.name isEqualToString:UIKeyboardWillHideNotification]||[note.name isEqualToString:UIKeyboardDidHideNotification];
 BOOL will=[note.name isEqualToString:UIKeyboardWillShowNotification]||[note.name isEqualToString:UIKeyboardWillChangeFrameNotification];
 BOOL did=[note.name isEqualToString:UIKeyboardDidShowNotification]||[note.name isEqualToString:UIKeyboardDidChangeFrameNotification];
 UIView *view=hide?editingView:responder();UIWindowScene *scene=view.window.windowScene?:editingScene;
 if(!scene){ignored(note,@"no-scene");return NO;}
 if(scene.screen!=UIScreen.mainScreen){ignored(note,@"not-main-screen");return NO;}
 if(scene.interfaceOrientation!=UIInterfaceOrientationPortrait){ignored(note,@"not-portrait");return NO;}
 id value=raw[UIKeyboardFrameEndUserInfoKey];if(![value isKindOfClass:NSValue.class]){ignored(note,@"no-end-frame");return NO;}
 if([note.object isKindOfClass:UIScreen.class]&&note.object!=scene.screen){ignored(note,@"foreign-screen");return NO;}
 CGRect screenFrame=[value CGRectValue];
 STHVRect diagnostic=vr([scene.screen.coordinateSpace convertRect:screenFrame toCoordinateSpace:scene.screen.fixedCoordinateSpace]);
 STHVSnapshot authority={0};BOOL hasHost=STHVReadLayout(bundle(),&authority);
 STHVLog(@"client-source",bundle(),@{@"notification":note.name,@"appRawDiagnostic":STHVRectJSON(diagnostic),@"physicalGeneration":@(hasHost?authority.physicalGeneration:0),@"sbVisible":@(hasHost&&authority.keyboardVisible),@"sbPhysical":STHVRectJSON(hasHost?authority.keyboard:(STHVRect){0}),@"layoutSerial":@(hasHost?authority.serial:0),@"scene":STHVRectJSON(vr(scene.coordinateSpace.bounds)),@"unmodifiedScreen":STHVRectJSON(vr(STHVUnmodifiedScreenBounds(scene.screen)))});
 BOOL explicitHidden=hasHost&&STHVClientAuthorityMode(authority.hosted,authority.card,vr(scene.coordinateSpace.bounds),vr(STHVUnmodifiedScreenBounds(scene.screen)),authority.physicalGeneration,authority.keyboardVisible)==STHVClientHidden;
 BOOL own=STHVRequestOwner()==STHVKey(bundle());
 BOOL live=hasHost&&authority.keyboardVisible&&authority.physicalGeneration&&own&&ready(view);
 STHVRect canonical={0};BOOL mapped=NO;NSString *deliveryName=note.name;
 if(hide&&!live){
  BOOL was=mappedSession;visible=NO;predictionPending=NO;sessionGeneration++;stopLease();STHVPublishRequest(bundle(),NO,(STHVRect){0});
  physicalFrame=(STHVRect){0};resetCorrection();
  STHVRect bounds=vr(scene.coordinateSpace.bounds);canonical=(STHVRect){bounds.x,bounds.y+bounds.h,bounds.w,0};mapped=was;
 }else{
  if(!ready(view)){ignored(note,@"no-responder");return NO;}
  editingView=view;editingScene=scene;startLease();
  // Real editing and Will events claim intent, never physical geometry.
  // Even a valid-looking or screen-off app frame is diagnostic only.
  if(will)STHVPublishRequest(bundle(),YES,(STHVRect){0});
  if(explicitHidden){
   STHVRect b=vr(scene.coordinateSpace.bounds);canonical=(STHVRect){b.x,b.y+b.h,b.w,0};mapped=YES;
   physicalFrame=(STHVRect){0};visible=NO;predictionPending=NO;
   deliveryName=will?UIKeyboardWillChangeFrameNotification:UIKeyboardDidChangeFrameNotification;
  }else mapped=mapFrame(scene,will&&!mappedSession,&canonical);
  if(hide&&live)deliveryName=[note.name isEqualToString:UIKeyboardWillHideNotification]?UIKeyboardWillChangeFrameNotification:UIKeyboardDidChangeFrameNotification;
 }
 STHVPublishClientFrames(bundle(),diagnostic,mapped?canonical:(STHVRect){0},authority.physicalGeneration);
 if(!mapped){
  if(hide&&!live)mappedSession=NO;
  // The frame an application computed for itself is not the panel that is
  // drawn. For a keyboard hosted by another process UIKit subtracts the tool
  // row and the candidate row that input method draws for itself, so an
  // application that lays out from its own notification stops forty to sixty
  // points short of the panel and its composer stays under the keys. Only the
  // physical frame SpringBoard observed describes what is on screen, so that
  // frame is mapped into this scene and delivered whenever it stands higher
  // than the frame the application brought with it. Timing and curve stay the
  // application's own.
  if(!hide&&hasHost&&STHVPhysicalFloor(scene,&authority,&lastSceneFrame)){
   CGFloat floorTop=notificationFrame(scene,lastSceneFrame).origin.y;
   if(floorTop<screenFrame.origin.y-0.5){
    STHVRect floorFrame=lastSceneFrame;
    physicalFrame=authority.keyboard;visible=YES;mappedSession=YES;editingView=view;editingScene=scene;startLease();
    if(will)STHVPublishRequest(bundle(),YES,(STHVRect){0});
    if(!localizedForeign++)STHVLog(@"client-physical-floor",bundle(),@{@"notification":note.name,@"appTop":@(screenFrame.origin.y),@"physicalTop":@(floorTop),@"appRawDiagnostic":STHVRectJSON(diagnostic),@"delivered":STHVRectJSON(floorFrame),@"physicalGeneration":@(authority.physicalGeneration)});
    NSDictionary *info=frameInfo(raw,scene,floorFrame,floorFrame);
    deliver(center,[NSNotification notificationWithName:note.name object:note.object userInfo:info]);
    probe(@"client-floor-delivery",@{@"notification":note.name,@"appRawDiagnostic":STHVRectJSON(diagnostic),@"deliveredScreen":STHVRectJSON(vr(notificationFrame(scene,floorFrame))),@"physicalGeneration":@(authority.physicalGeneration)});
    if(did)scheduleReconcile();
    return YES;
   }
  }
  // Handing over the application's own frame untouched, with the locality flag
  // corrected, is the smallest change that lets an application lay out for a
  // keyboard it would otherwise discard. The frame, the timing and the curve are
  // the ones the system already sent, so no animation is rewritten.
  if(foreign&&ready(view)){
   NSMutableDictionary *localized=[raw mutableCopy];
   localized[UIKeyboardIsLocalUserInfoKey]=@YES;
   if(!localizedForeign++)STHVLog(@"client-foreign-localized",bundle(),@{@"notification":note.name,@"reason":@"non-local",@"appRawDiagnostic":STHVRectJSON(diagnostic),@"physicalGeneration":@(hasHost?authority.physicalGeneration:0),@"scene":STHVRectJSON(vr(scene.coordinateSpace.bounds))});
   editingView=view;editingScene=scene;startLease();
   if(will)STHVPublishRequest(bundle(),YES,(STHVRect){0});
   deliver(center,[NSNotification notificationWithName:note.name object:note.object userInfo:localized]);
   probe(@"client-foreign-delivery",@{@"notification":note.name,@"appRawDiagnostic":STHVRectJSON(diagnostic),@"physicalGeneration":@(authority.physicalGeneration)});
   if(hide)resetCorrection();
   if(did)scheduleReconcile();
   return YES;
  }
  if(will||hide)probe(@"client-awaiting-sb-authority",@{@"appRawDiagnostic":STHVRectJSON(diagnostic),@"notification":note.name});
  return NO;
 }
 STHVRect prior=mappedSession?lastSceneFrame:canonical;
 if(!mappedSession&&!hide){STHVRect b=vr(scene.coordinateSpace.bounds);prior=(STHVRect){b.x,b.y+b.h,b.w,0};}
 NSDictionary *info=frameInfo(raw,scene,prior,canonical);
 lastSceneFrame=canonical;mappedSession=!explicitHidden&&(!hide||live);
 realMetadata=raw;
 deliver(center,[NSNotification notificationWithName:deliveryName object:note.object userInfo:info]);
 probe(hide?@"client-hide-observation":(will?@"client-will":@"client-did"),@{@"notification":note.name,@"deliveredNotification":deliveryName,@"appRawDiagnostic":STHVRectJSON(diagnostic),@"deliveredScreen":STHVRectJSON(vr(notificationFrame(scene,canonical))),@"sceneInset":@(STHVInset(canonical,vr(scene.coordinateSpace.bounds))),@"physicalGeneration":@(authority.physicalGeneration)});
 if(did){NSUInteger generation=++sessionGeneration;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(generation==sessionGeneration&&visible)probe(@"client-settled",nil);});scheduleReconcile();}
 if(hide&&!live)realMetadata=nil;
 return YES;
}
static void post(id center,SEL selector,NSNotification *note){if(!intercept(center,note))systemPost(center,selector,note);}
static void postName(id center,SEL selector,NSString *name,id object,NSDictionary *info){
 if(!insideDelivery&&keyboardEvent(name)&&intercept(center,[NSNotification notificationWithName:name object:object userInfo:info]))return;
 systemPostName(center,selector,name,object,info);
}
static CGFloat inset(id object,SEL selector,UIWindowScene *scene,BOOL *minimum,BOOL ignoreX){
 CGFloat native=systemInset(object,selector,scene,minimum,ignoreX);
 if(!NSThread.isMainThread||scene!=editingScene||!ready(editingView))return native;
 STHVSnapshot authority={0};
 if(STHVReadLayout(bundle(),&authority)&&STHVClientAuthorityMode(authority.hosted,authority.card,vr(scene.coordinateSpace.bounds),vr(STHVUnmodifiedScreenBounds(scene.screen)),authority.physicalGeneration,authority.keyboardVisible)==STHVClientHidden){if(minimum)*minimum=YES;return 0;}
 STHVRect canonical;
 if(!mapFrame(scene,NO,&canonical)){
  // A measured shortfall still has to reach the layout, even when the scene
  // needs no mapping: the application asked for an inset and gets the native one
  // plus the correction this session measured.
  if(correctionLift>0){if(minimum)*minimum=NO;return native+correctionLift;}
  return native;
 }
 double amount=STHVInset(canonical,vr(scene.coordinateSpace.bounds))+correctionLift;
 if(minimum)*minimum=amount<=0;return amount;
}
static NSString *lastHostSkip;
static void hostSkip(NSString *reason){
 if([lastHostSkip isEqual:reason])return;
 lastHostSkip=reason;
 STHVLog(@"client-host-skip",bundle(),@{@"reason":reason,@"visible":@(visible),@"mapped":@(mappedSession),@"scene":STHVRectJSON(lastSceneFrame),@"physical":STHVRectJSON(physicalFrame)});
}
static void hostChanged(void){
 if(!NSThread.isMainThread||insideDelivery||!ready(editingView))return;
 UIWindowScene *scene=editingView.window.windowScene;STHVSnapshot host={0};
 if(!STHVReadLayout(bundle(),&host)){hostSkip(@"no-host-snapshot");return;}
 BOOL samePrediction=predictionPending&&host.serial==predictionSerial&&STHVRequestOwner()==STHVKey(bundle());
 if((!host.active&&!samePrediction)||!host.hosted||!host.keyboardVisible||!host.physicalGeneration||!STHVValid(host.card)){
  if(!mappedSession)hostSkip(@"host-not-driving");
  if(mappedSession){
   STHVRect bounds=vr(scene.coordinateSpace.bounds),end={bounds.x,bounds.y+bounds.h,bounds.w,0};
   NSMutableDictionary *metadata=realMetadata?[realMetadata mutableCopy]:[NSMutableDictionary new];
   metadata[UIKeyboardAnimationDurationUserInfoKey]=@0;
   NSDictionary *info=frameInfo(metadata,scene,lastSceneFrame,end);
   mappedSession=NO;visible=NO;predictionPending=NO;stopLease();lastSceneFrame=end;
   for(NSString *name in @[UIKeyboardWillHideNotification,UIKeyboardWillChangeFrameNotification,UIKeyboardDidChangeFrameNotification,UIKeyboardDidHideNotification])deliver(NSNotificationCenter.defaultCenter,[NSNotification notificationWithName:name object:scene.screen userInfo:info]);
   probe(@"client-host-inactive",nil);
  }
  return;
 }
 // One layout target for UIKit's inset API and all notification observers.
 // The app lays out the complete composer/background itself; no leaf is moved.
 if(!visible&&host.active&&host.keyboardVisible&&host.physicalGeneration){physicalFrame=host.keyboard;visible=YES;startLease();}
 if(!visible){hostSkip(@"no-visible-session");return;}
 STHVRect canonical;if(!mapFrame(scene,NO,&canonical)){hostSkip(@"unmapped");return;}
 if(mappedSession&&STHVNear(canonical,lastSceneFrame,.5))return;
 STHVRect begin=mappedSession?lastSceneFrame:canonical;
 NSMutableDictionary *metadata=realMetadata?[realMetadata mutableCopy]:[NSMutableDictionary new];
 metadata[UIKeyboardAnimationDurationUserInfoKey]=@0;
 if(!metadata[UIKeyboardAnimationCurveUserInfoKey])metadata[UIKeyboardAnimationCurveUserInfoKey]=@0;
 metadata[UIKeyboardIsLocalUserInfoKey]=@YES;
 NSDictionary *info=frameInfo(metadata,scene,begin,canonical);
 lastSceneFrame=canonical;mappedSession=YES;editingScene=scene;
 // A fresh canonical frame from the host replaces whatever this session had
 // measured, so the measurement starts again instead of stacking on top of it.
 correctionLift=0;corrections=0;lastFixField=(STHVRect){0};
 for(NSString *name in @[UIKeyboardWillChangeFrameNotification,UIKeyboardDidChangeFrameNotification]){
  deliver(NSNotificationCenter.defaultCenter,[NSNotification notificationWithName:name object:scene.screen userInfo:info]);
 }
 lastHostSkip=nil;
 probe(@"client-host-commit",nil);
 scheduleReconcile();
}
static void editingBegan(NSNotification *note){
 BOOL isView=[note.object isKindOfClass:UIView.class];
 BOOL usable=isView&&ready(note.object);
 gapSamples=0;gapWorst=0;
 STHVLog(@"client-editing-began",bundle(),@{@"usable":@(usable),@"class":isView?NSStringFromClass([(UIView *)note.object class]):@"-"});
 if(!usable)return;
 editingView=note.object;editingScene=editingView.window.windowScene;sessionGeneration++;
 STHVPublishRequest(bundle(),YES,(STHVRect){0});startLease();
}
static void editingEnded(NSNotification *note){
 STHVLog(@"client-editing-ended",bundle(),@{@"sameView":@(note.object==editingView),@"class":note.object?NSStringFromClass([note.object class]):@"-"});
 if(note.object!=editingView)return;
 NSUInteger generation=++sessionGeneration;
 dispatch_async(dispatch_get_main_queue(),^{
  if(generation!=sessionGeneration||ready(editingView))return;
  UIView *next=responder();if(next){editingView=next;editingScene=next.window.windowScene;return;}
  STHVPublishRequest(bundle(),NO,(STHVRect){0});stopLease();visible=NO;mappedSession=NO;physicalFrame=(STHVRect){0};
  resetCorrection();
 });
}
#if !defined(STH_VIEWPORT_CLIENT_TEST)
static void activateClient(void){
 static BOOL installed;
 if(installed)return;
 if(!NSThread.isMainThread){STHVLog(@"client-inactive",bundle(),@{@"reason":@"off-main"});return;}
 // An application that never installs is the other way a keyboard session loses
 // its client half; the reason is recorded instead of returning in silence.
 if(!STHVApplicationBundleAllowed(NSBundle.mainBundle)){STHVLog(@"client-inactive",bundle(),@{@"reason":@"bundle-not-allowed"});return;}
 installed=YES;NSString *name=bundle();
  Method p=class_getInstanceMethod(NSNotificationCenter.class,@selector(postNotification:));
  Method n=class_getInstanceMethod(NSNotificationCenter.class,@selector(postNotificationName:object:userInfo:));
  if(!p||!n)return;
  systemPost=(void *)method_getImplementation(p);systemPostName=(void *)method_getImplementation(n);
  method_setImplementation(p,(IMP)post);method_setImplementation(n,(IMP)postName);
  Class remote=NSClassFromString(@"_UIRemoteKeyboards");
  SEL selector=NSSelectorFromString(@"intersectionHeightForWindowScene:isLocalMinimumHeightOut:ignoreHorizontalOffset:");
  Method m=class_getInstanceMethod(remote,selector);char type[16]={0};if(m)method_getReturnType(m,type,sizeof(type));
  if(m&&method_getNumberOfArguments(m)==5&&!strcmp(type,@encode(CGFloat))){systemInset=(void *)method_getImplementation(m);method_setImplementation(m,(IMP)inset);}
  for(NSString *event in @[UITextFieldTextDidBeginEditingNotification,UITextViewTextDidBeginEditingNotification])
   [NSNotificationCenter.defaultCenter addObserverForName:event object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){editingBegan(note);}];
  for(NSString *event in @[UITextFieldTextDidEndEditingNotification,UITextViewTextDidEndEditingNotification])
   [NSNotificationCenter.defaultCenter addObserverForName:event object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){editingEnded(note);}];
  STHVObserveLayout(name,^{hostChanged();});
  NSMutableArray *legacy=[NSMutableArray new];
  NSSet *retired=[NSSet setWithArray:@[@"SthenoKeyboard.dylib",@"SthenoKb.dylib",@"KeyboardFix.dylib",@"SthenoKeyboardInset.dylib"]];
  for(uint32_t i=0;i<_dyld_image_count();i++){const char *image=_dyld_get_image_name(i);if(!image)continue;NSString *leaf=[NSString stringWithUTF8String:image].lastPathComponent;if([retired containsObject:leaf])[legacy addObject:leaf];}
  STHVLog(@"client-loaded-images",name,@{@"legacyKeyboardImages":legacy});
  STHVLog(@"client-start",name,@{@"architecture":@"viewport33",@"activation":@"observed-post-launch",@"insetHookAvailable":@(systemInset!=NULL),@"editorTransforms":@NO,@"legacyLibraryRequired":@NO,@"home":NSHomeDirectory()});
  STHVInstallAppSceneReflow();
}
__attribute__((constructor)) static void installClient(void){
 @autoreleasepool{
  STHVObserveApplicationLaunch(NSBundle.mainBundle,NSNotificationCenter.defaultCenter,
   @[UIApplicationDidFinishLaunchingNotification,UIApplicationDidBecomeActiveNotification,UISceneDidActivateNotification],^{activateClient();});
 }
}
#endif
