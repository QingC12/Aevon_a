// Geometry only. Never reads text, accessibility labels or conversation data.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "LayoutBus.h"
#import "EditorAssembly.h"
static __weak UIResponder *capturedResponder;
@interface UIResponder (STHEditorProbe)
-(void)sth_captureEditorProbe:(id)sender;
@end
@implementation UIResponder (STHEditorProbe)
-(void)sth_captureEditorProbe:(id)sender {capturedResponder=self;}
@end
@interface STHGuardTransform:NSObject
@property CGAffineTransform original;
@property CGAffineTransform applied;
@property double sceneY;
@end
@implementation STHGuardTransform
@end
static NSMapTable<UIView *,STHGuardTransform *> *adjustments;
static __weak UIView *lastComposer;
static CADisplayLink *display;
static BOOL active;
static CFTimeInterval fastUntil,lastTick,lastReport;
static int lastStage;
extern BOOL STHMeasuredKeyboardScene(UIWindowScene *,CGRect *,double *);
static CGRect measuredCandidate;
static __weak UIWindowScene *measuredScene;
static CFTimeInterval measuredAt;
static BOOL haveMeasured;
static BOOL shown(UIView *v){return v&&!v.hidden&&v.alpha>.01&&v.window;}
static BOOL keyboardWindow(UIWindow *w){return [NSStringFromClass(w.class) containsString:@"Keyboard"];}
static BOOL editing(UIView *v){return v&&([v isKindOfClass:UITextField.class]||[v isKindOfClass:UITextView.class]||[v conformsToProtocol:@protocol(UITextInput)]);}
static STHRect rr(CGRect r){return (STHRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
static void restoreView(UIView *v){
 STHGuardTransform *s=[adjustments objectForKey:v];if(!s)return;
 if(CGAffineTransformEqualToTransform(v.transform,s.applied))
  [UIView performWithoutAnimation:^{v.transform=s.original;}];
 [adjustments removeObjectForKey:v];
}
static void restoreAll(void){for(UIView *v in adjustments.keyEnumerator.allObjects)restoreView(v);lastComposer=nil;}
static CGRect baseline(UIView *v,id<UICoordinateSpace> scene){
 STHGuardTransform *s=[adjustments objectForKey:v];
 if(s&&!CGAffineTransformEqualToTransform(v.transform,s.applied)){
  [adjustments removeObjectForKey:v];s=nil; // app took ownership, do not restore stale transform
 }
 CGRect r=[v convertRect:v.bounds toCoordinateSpace:scene];if(s)r.origin.y-=s.sceneY;return r;
}
static UIView *focusedIn(UIView *v,int depth,int *budget){
 if(!shown(v)||depth>24||--*budget<0)return nil;
 // Do not let a noneditable first responder terminate the whole scene search.
 if(v.isFirstResponder&&editing(v))return v;
 for(UIView *child in v.subviews){if(*budget<=0)break;UIView *f=focusedIn(child,depth+1,budget);if(f)return f;}
 return nil;
}
static UIView *currentEditor(void){
 capturedResponder=nil;
 [UIApplication.sharedApplication sendAction:@selector(sth_captureEditorProbe:) to:nil from:nil forEvent:nil];
 UIResponder *r=capturedResponder;
 if([r isKindOfClass:UIView.class]&&editing((UIView *)r)&&shown((UIView *)r))return (UIView *)r;
 // UIKit delegates the input responder to non-view hosts in some custom editors.
 for(int i=0;r&&i<16;i++,r=r.nextResponder){
  if([r isKindOfClass:UIView.class]){int budget=800;UIView *f=focusedIn((UIView *)r,0,&budget);if(f)return f;}
 }
 for(UIScene *s in UIApplication.sharedApplication.connectedScenes){
  if(![s isKindOfClass:UIWindowScene.class])continue;
  for(UIWindow *w in ((UIWindowScene *)s).windows){
   if(!shown(w)||keyboardWindow(w))continue;
   int budget=1800;UIView *f=focusedIn(w,0,&budget);if(f)return f;
  }
 }
 return nil;
}
static BOOL rowEvidence(UIView *v,int depth,int *budget){
 if(!shown(v)||depth>3||--*budget<0)return NO;
 NSString *n=NSStringFromClass(v.class).lowercaseString;
 if([v isKindOfClass:UIControl.class]||v.gestureRecognizers.count||[n containsString:@"toolbar"]||
   [n containsString:@"emoji"]||[n containsString:@"emotion"]||[n containsString:@"emoticon"]||
   [n containsString:@"inputaccessory"])return YES;
 for(UIView *c in v.subviews)if(rowEvidence(c,depth+1,budget))return YES;
 return NO;
}
static void collectRows(UIView *v,UIView *root,int depth,int *budget,NSMutableArray *possible){
 if(!shown(v)||depth>3||--*budget<0||v==root||[v isDescendantOfView:root])return;
 if(![root isDescendantOfView:v]){
  // An app emoji strip can itself be a collection/scroll view. Allow it as
  // an ATTACHED ROW, but the strict height/adjacency test below still excludes
  // the main conversation/comment scroll page and unrelated siblings.
  int b=150;if(rowEvidence(v,0,&b))[possible addObject:v];
 }
 for(UIView *c in v.subviews){if(*budget<=0)break;collectRows(c,root,depth+1,budget,possible);}
}
static NSArray<UIView *> *assembly(UIView *root,UIWindowScene *scene,CGRect *bounds){
 CGRect group=baseline(root,scene.coordinateSpace);
 NSMutableArray<UIView *> *candidates=[NSMutableArray new],*result=[NSMutableArray arrayWithObject:root];
 // Up to3 bounded ancestor branches; never search a separate app/window for rows.
 UIView *ancestor=root.superview;
 for(int i=0;ancestor&&ancestor!=root.window&&i<3;i++,ancestor=ancestor.superview){
  int budget=350;collectRows(ancestor,root,0,&budget,candidates);
 }
 for(int pass=0;pass<4;pass++)for(UIView *row in candidates){
  BOOL overlapsTree=NO;
  for(UIView *used in result)if(row==used||[row isDescendantOfView:used]||[used isDescendantOfView:row]){overlapsTree=YES;break;}
  if(overlapsTree)continue;
  CGRect r=baseline(row,scene.coordinateSpace);int budget=100;
  if(STHEditorAttachedRow(rr(group),rr(r),scene.coordinateSpace.bounds.size.height,rowEvidence(row,0,&budget))){
   [result addObject:row];group=CGRectUnion(group,r);
  }
 }
 *bounds=group;return result;
}
static BOOL moveView(UIView *view,UIWindowScene *scene,double lift){
 STHGuardTransform *s=[adjustments objectForKey:view];
 if(!s){s=[STHGuardTransform new];s.original=view.transform;s.applied=view.transform;s.sceneY=0;[adjustments setObject:s forKey:view];}
 if(fabs(s.sceneY+lift)<.5)return NO;
 CGPoint a=[view.superview convertPoint:CGPointZero fromCoordinateSpace:scene.coordinateSpace];
 CGPoint b=[view.superview convertPoint:CGPointMake(0,-lift) fromCoordinateSpace:scene.coordinateSpace];
 CGAffineTransform t=s.original;t.tx+=b.x-a.x;t.ty+=b.y-a.y;
 s.applied=t;s.sceneY=-lift;
 [UIView performWithoutAnimation:^{view.transform=t;}];return YES;
}
static void report(int stage,CGRect r,double top,double lift,unsigned rows){
 double now=CACurrentMediaTime();if(stage==lastStage&&now-lastReport<.5)return;
 lastStage=stage;lastReport=now;
 STHReportEditor(NSBundle.mainBundle.bundleIdentifier,stage,r,top,lift,rows);
 STHWriteLayoutLog([NSString stringWithFormat:@"editor-stage=%d frame=%@ keysTop=%.3f appliedLift=%.3f rows=%u",stage,NSStringFromCGRect(r),top,lift,rows]);
}
@interface STHPersistentEditorGuard:NSObject
+(void)tick:(CADisplayLink *)link;
@end
@implementation STHPersistentEditorGuard
+(void)tick:(CADisplayLink *)sender{
 double now=CACurrentMediaTime();if(!active)return;
 //30Hz while showing/updating,10Hz thereafter for editors mounted late. Stop
 // on hide/expired host: no scanning unrelated full-screen applications.
 if(now-lastTick<(now<fastUntil?.028:.095))return;lastTick=now;
 int phase=STHLayoutStatus(NSBundle.mainBundle.bundleIdentifier);
 if(!phase){active=NO;[display invalidate];display=nil;restoreAll();report(6,CGRectZero,0,0,0);return;}
 if(phase!=1){report(1,CGRectZero,0,0,0);return;}
 UIView *field=currentEditor();
 if(!field){restoreAll();report(2,CGRectZero,0,0,0);return;}
 UIWindow *window=field.window;UIWindowScene *scene=window.windowScene;
 if(!scene||keyboardWindow(window)||!UIInterfaceOrientationIsPortrait(scene.interfaceOrientation))return;
 CGRect keys;double inset=0;
 if(!STHReadLayout(NSBundle.mainBundle.bundleIdentifier,scene.coordinateSpace.bounds,&keys,&inset)){report(1,CGRectZero,0,0,0);return;}
 CGRect measuredKeys;double measuredInset=0;
 if(STHMeasuredKeyboardScene(scene,&measuredKeys,&measuredInset)){
  BOOL same=haveMeasured&&measuredScene==scene&&fabs(measuredKeys.origin.y-measuredCandidate.origin.y)<=.5&&
   fabs(measuredKeys.size.height-measuredCandidate.size.height)<=.5;
  if(!same){measuredCandidate=measuredKeys;measuredAt=now;haveMeasured=YES;measuredScene=scene;}
  // Use only repeated current samples. Do not permanently lock the first563
  // or warm590 source; no synthetic27pt compensation.
  else if(now-measuredAt>=.06){keys=measuredKeys;inset=measuredInset;}
 }else haveMeasured=NO;
 UIView *root=nil;
 for(UIView *v=field;v&&v!=window;v=v.superview){
  CGRect r=baseline(v,scene.coordinateSpace);
  if(r.size.height>fmin(320,scene.coordinateSpace.bounds.size.height*.46))break;
  if(STHEditorContainer(r.size.width,r.size.height,scene.coordinateSpace.bounds.size.width,
      scene.coordinateSpace.bounds.size.height,[v isKindOfClass:UIScrollView.class]))root=v;
 }
 if(!root||!root.superview){restoreAll();report(3,[field convertRect:field.bounds toCoordinateSpace:scene.coordinateSpace],keys.origin.y,0,0);return;}
 if(lastComposer!=root){restoreAll();lastComposer=root;}
 CGRect original;NSArray<UIView *> *views=assembly(root,scene,&original);
 // A removed/reparented toolbar must not retain an old transform.
 for(UIView *old in adjustments.keyEnumerator.allObjects)if(![views containsObject:old])restoreView(old);
 double lift=STHComposerLift(original.origin.y,CGRectGetMaxY(original),keys.origin.y,scene.coordinateSpace.bounds.size.height);
 BOOL changed=NO;
 if(!adjustments)adjustments=[NSMapTable weakToStrongObjectsMapTable];
 for(UIView *v in views){if(v.superview)changed=moveView(v,scene,lift)||changed;}
 CGRect measured=CGRectNull;
 for(UIView *v in views){CGRect r=[v convertRect:v.bounds toCoordinateSpace:scene.coordinateSpace];measured=CGRectIsNull(measured)?r:CGRectUnion(measured,r);}
 report(changed?5:4,measured,keys.origin.y,lift,(unsigned)views.count-1);
}
@end
void STHEditorVisibilityLegacyEvent(BOOL showing){
 if(![NSThread isMainThread])return;
 if(!showing){active=NO;haveMeasured=NO;measuredScene=nil;[display invalidate];display=nil;restoreAll();report(6,CGRectZero,0,0,0);return;}
 if(!active){active=YES;lastTick=0;report(1,CGRectZero,0,0,0);}
 fastUntil=CACurrentMediaTime()+1.2;
 if(!display){display=[CADisplayLink displayLinkWithTarget:STHPersistentEditorGuard.class selector:@selector(tick:)];
  display.preferredFramesPerSecond=30;[display addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];}
}
static id focusFieldObserver,focusTextObserver;
__attribute__((constructor)) static void editorGuardReady(void){
 extern BOOL STHRefinementEnabled(void);if(STHRefinementEnabled())return;
 dispatch_async(dispatch_get_main_queue(),^{
  void(^focus)(NSNotification *)=^(NSNotification *note){
   if(STHLayoutStatus(NSBundle.mainBundle.bundleIdentifier)>0)STHEditorVisibilityLegacyEvent(YES);
  };
  focusFieldObserver=[NSNotificationCenter.defaultCenter addObserverForName:UITextFieldTextDidBeginEditingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:focus];
  focusTextObserver=[NSNotificationCenter.defaultCenter addObserverForName:UITextViewTextDidBeginEditingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:focus];
 });
}
