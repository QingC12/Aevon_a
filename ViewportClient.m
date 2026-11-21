// New viewport keyboard client. No editor/view transforms or per-app profiles.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "ViewportBus.h"
#import "ViewportDiagnostics.h"
static __weak UIView *editingView;
static __weak UIWindowScene *editingScene;
static BOOL visible,mappedSession,insideDelivery,predictionPending;
static uint64_t predictionSerial;
static STHVRect physicalFrame,lastSceneFrame;
static NSDictionary *realMetadata;
static dispatch_source_t leaseTimer;
static NSUInteger sessionGeneration;
static void (*systemPost)(id,SEL,NSNotification *);
static void (*systemPostName)(id,SEL,NSString *,id,NSDictionary *);
static CGFloat (*systemInset)(id,SEL,UIWindowScene *,BOOL *,BOOL);
static STHVRect vr(CGRect r){return (STHVRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
static CGRect cr(STHVRect r){return CGRectMake(r.x,r.y,r.w,r.h);}
static NSString *bundle(void){return NSBundle.mainBundle.bundleIdentifier;}
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
static BOOL mapFrame(UIWindowScene *scene,STHVRect physical,BOOL firstWill,STHVRect *mapped){
 if(!scene||scene.screen!=UIScreen.mainScreen||scene.interfaceOrientation!=UIInterfaceOrientationPortrait||!STHVKeyboard(physical,vr(scene.screen.fixedCoordinateSpace.bounds)))return NO;
 STHVSnapshot host={0};if(!STHVReadLayout(bundle(),&host)||!STHVValid(host.card))return NO;
 if(firstWill&&!host.active){predictionPending=YES;predictionSerial=host.serial;}
 if(host.active)predictionPending=NO;
 BOOL predict=predictionPending&&host.serial==predictionSerial&&STHVRequestOwner()==STHVKey(bundle());
 STHVRect card=host.active||!predict?host.card:STHVTarget(host.card,vr(scene.screen.fixedCoordinateSpace.bounds),physical);
 if(!STHVValid(card))return NO;
 *mapped=STHVMap(card,physical,vr(scene.coordinateSpace.bounds));return YES;
}
static CGRect notificationFrame(UIWindowScene *scene,STHVRect mapped){
 // Keyboard notification frames are screen coordinates, not scene coordinates.
 // Convert the canonical scene frame back to the screen before delivery so an
 // application's own screen->view conversion runs exactly once.
 return [scene.coordinateSpace convertRect:cr(mapped) toCoordinateSpace:scene.screen.coordinateSpace];
}
static NSDictionary *frameInfo(NSDictionary *raw,UIWindowScene *scene,STHVRect begin,STHVRect end){
 NSMutableDictionary *info=raw?[raw mutableCopy]:[NSMutableDictionary new];
 info[UIKeyboardFrameBeginUserInfoKey]=[NSValue valueWithCGRect:notificationFrame(scene,begin)];
 info[UIKeyboardFrameEndUserInfoKey]=[NSValue valueWithCGRect:notificationFrame(scene,end)];
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
  if(!visible||!ready(editingView)){stopLease();STHVPublishRequest(bundle(),NO,(STHVRect){0});return;}
  // Renewal never writes the shared owner. A former fullscreen app cannot
  // steal input back from a newly focused floating card through a heartbeat.
  if(!STHVRenewRequest(bundle(),physicalFrame)&&!STHVResumeRequest(bundle(),physicalFrame)){
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
static BOOL intercept(NSNotificationCenter *center,NSNotification *note){
 if(insideDelivery||center!=NSNotificationCenter.defaultCenter||!NSThread.isMainThread||!keyboardEvent(note.name))return NO;
 NSDictionary *raw=note.userInfo;if(![raw isKindOfClass:NSDictionary.class]||[raw[UIKeyboardIsLocalUserInfoKey] isEqual:@NO])return NO;
 BOOL hide=[note.name isEqualToString:UIKeyboardWillHideNotification]||[note.name isEqualToString:UIKeyboardDidHideNotification];
 BOOL will=[note.name isEqualToString:UIKeyboardWillShowNotification]||[note.name isEqualToString:UIKeyboardWillChangeFrameNotification];
 BOOL did=[note.name isEqualToString:UIKeyboardDidShowNotification]||[note.name isEqualToString:UIKeyboardDidChangeFrameNotification];
 UIView *view=hide?editingView:responder();UIWindowScene *scene=view.window.windowScene?:editingScene;
 if(!scene||scene.screen!=UIScreen.mainScreen||scene.interfaceOrientation!=UIInterfaceOrientationPortrait)return NO;
 if(did&&STHVRequestOwner()!=STHVKey(bundle()))return NO;
 id value=raw[UIKeyboardFrameEndUserInfoKey];if(![value isKindOfClass:NSValue.class])return NO;
 if([note.object isKindOfClass:UIScreen.class]&&note.object!=scene.screen)return NO;
 CGRect screenFrame=[value CGRectValue];
 STHVRect physical=vr([scene.screen.coordinateSpace convertRect:screenFrame toCoordinateSpace:scene.screen.fixedCoordinateSpace]);
 STHVRect canonical={0};BOOL mapped=NO;
 if(hide){
  BOOL was=mappedSession;visible=NO;predictionPending=NO;sessionGeneration++;stopLease();STHVPublishRequest(bundle(),NO,(STHVRect){0});
  physicalFrame=(STHVRect){0};
  STHVRect bounds=vr(scene.coordinateSpace.bounds);canonical=(STHVRect){bounds.x,bounds.y+bounds.h,bounds.w,0};
  mapped=was;
 }else{
  if(!ready(view))return NO;
  if(!STHVKeyboard(physical,vr(scene.screen.fixedCoordinateSpace.bounds))){
   if(visible||mappedSession){visible=NO;mappedSession=NO;predictionPending=NO;physicalFrame=(STHVRect){0};stopLease();STHVPublishRequest(bundle(),NO,(STHVRect){0});probe(@"client-native-keyboard-context",nil);}
   return NO;
  }
  editingView=view;editingScene=scene;physicalFrame=physical;visible=YES;startLease();
  if(will)STHVPublishRequest(bundle(),YES,physical);
  mapped=mapFrame(scene,physical,will&&!mappedSession,&canonical);
 }
 if(!mapped){
  if(hide)mappedSession=NO;
  if(will||hide)probe(@"client-unmapped-native",@{@"rawScreen":STHVRectJSON(vr(screenFrame)),@"owner":@(STHVRequestOwner())});
  return NO;
 }
 STHVRect prior=mappedSession?lastSceneFrame:canonical;
 if(!mappedSession&&!hide){STHVRect b=vr(scene.coordinateSpace.bounds);prior=(STHVRect){b.x,b.y+b.h,b.w,0};}
 NSDictionary *info=frameInfo(raw,scene,prior,canonical);
 lastSceneFrame=canonical;mappedSession=!hide;
 if(!hide)realMetadata=raw;
 deliver(center,[NSNotification notificationWithName:note.name object:note.object userInfo:info]);
 if(will||did||hide){
  probe(hide?@"client-hide":(will?@"client-will":@"client-did"),@{@"rawScreen":STHVRectJSON(vr(screenFrame)),@"deliveredScreen":STHVRectJSON(vr(notificationFrame(scene,canonical))),@"sceneInset":@(STHVInset(canonical,vr(scene.coordinateSpace.bounds)))});
  if(did){NSUInteger generation=++sessionGeneration;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(generation==sessionGeneration&&visible)probe(@"client-settled",nil);});}
 }
 if(hide)realMetadata=nil;
 return YES;
}
static void post(id center,SEL selector,NSNotification *note){if(!intercept(center,note))systemPost(center,selector,note);}
static void postName(id center,SEL selector,NSString *name,id object,NSDictionary *info){
 if(!insideDelivery&&keyboardEvent(name)&&intercept(center,[NSNotification notificationWithName:name object:object userInfo:info]))return;
 systemPostName(center,selector,name,object,info);
}
static CGFloat inset(id object,SEL selector,UIWindowScene *scene,BOOL *minimum,BOOL ignoreX){
 CGFloat native=systemInset(object,selector,scene,minimum,ignoreX);
 if(!NSThread.isMainThread||!visible||!mappedSession||scene!=editingScene||!ready(editingView))return native;
 STHVRect canonical;if(!mapFrame(scene,physicalFrame,NO,&canonical))return native;
 double amount=STHVInset(canonical,vr(scene.coordinateSpace.bounds));
 if(minimum)*minimum=amount<=0;return amount;
}
static void hostChanged(void){
 if(!NSThread.isMainThread||insideDelivery||!ready(editingView))return;
 UIWindowScene *scene=editingView.window.windowScene;STHVSnapshot host={0};
 if(!STHVReadLayout(bundle(),&host))return;
 BOOL samePrediction=predictionPending&&host.serial==predictionSerial&&STHVRequestOwner()==STHVKey(bundle());
 if((!host.active&&!samePrediction)||!STHVValid(host.card)){
  if(mappedSession){
   STHVRect bounds=vr(scene.coordinateSpace.bounds),end={bounds.x,bounds.y+bounds.h,bounds.w,0};
   NSMutableDictionary *metadata=realMetadata?[realMetadata mutableCopy]:[NSMutableDictionary new];
   metadata[UIKeyboardAnimationDurationUserInfoKey]=@0;
   NSDictionary *info=frameInfo(metadata,scene,lastSceneFrame,end);
   mappedSession=NO;visible=NO;predictionPending=NO;stopLease();lastSceneFrame=end;
   for(NSString *name in @[UIKeyboardWillChangeFrameNotification,UIKeyboardDidChangeFrameNotification])deliver(NSNotificationCenter.defaultCenter,[NSNotification notificationWithName:name object:scene.screen userInfo:info]);
   probe(@"client-host-inactive",nil);
  }
  return;
 }
 // One layout target for UIKit's inset API and all notification observers.
 // The app lays out the complete composer/background itself; no leaf is moved.
 if(!visible&&host.active&&STHVKeyboard(host.keyboard,vr(scene.screen.bounds))){physicalFrame=host.keyboard;visible=YES;startLease();}
 if(!visible)return;
 STHVRect canonical;if(!mapFrame(scene,physicalFrame,NO,&canonical))return;
 if(mappedSession&&STHVNear(canonical,lastSceneFrame,.5))return;
 STHVRect begin=mappedSession?lastSceneFrame:canonical;
 NSMutableDictionary *metadata=realMetadata?[realMetadata mutableCopy]:[NSMutableDictionary new];
 metadata[UIKeyboardAnimationDurationUserInfoKey]=@0;
 if(!metadata[UIKeyboardAnimationCurveUserInfoKey])metadata[UIKeyboardAnimationCurveUserInfoKey]=@0;
 metadata[UIKeyboardIsLocalUserInfoKey]=@YES;
 NSDictionary *info=frameInfo(metadata,scene,begin,canonical);
 lastSceneFrame=canonical;mappedSession=YES;editingScene=scene;
 for(NSString *name in @[UIKeyboardWillChangeFrameNotification,UIKeyboardDidChangeFrameNotification]){
  deliver(NSNotificationCenter.defaultCenter,[NSNotification notificationWithName:name object:scene.screen userInfo:info]);
 }
 probe(@"client-host-commit",nil);
}
static void editingBegan(NSNotification *note){
 if(![note.object isKindOfClass:UIView.class]||!ready(note.object))return;
 editingView=note.object;editingScene=editingView.window.windowScene;sessionGeneration++;
 STHVPublishRequest(bundle(),YES,visible?physicalFrame:(STHVRect){0});
}
static void editingEnded(NSNotification *note){
 if(note.object!=editingView)return;
 NSUInteger generation=++sessionGeneration;
 dispatch_async(dispatch_get_main_queue(),^{
  if(generation!=sessionGeneration||ready(editingView))return;
  UIView *next=responder();if(next){editingView=next;editingScene=next.window.windowScene;return;}
  STHVPublishRequest(bundle(),NO,(STHVRect){0});stopLease();visible=NO;mappedSession=NO;physicalFrame=(STHVRect){0};
 });
}
__attribute__((constructor)) static void installClient(void){
 NSString *name=bundle();if(!name.length||[name isEqualToString:@"com.apple.springboard"]||[name isEqualToString:@"com.apple.UIKit.remote-keyboard"]||[name isEqualToString:@"com.apple.Spotlight"])return;
 dispatch_async(dispatch_get_main_queue(),^{
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
  STHVLog(@"client-start",name,@{@"architecture":@"viewport31",@"insetHookAvailable":@(systemInset!=NULL),@"editorTransforms":@NO,@"legacyLibraryRequired":@NO});
 });
}
