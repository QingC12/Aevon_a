// Geometry only. Never reads text, accessibility labels or conversation data.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "LayoutBus.h"
#import "EditorAssembly.h"
#import "EditorRefinement.h"
#import "EditorProfiles.h"
static __weak UIResponder *capturedResponder;
@interface UIResponder (STHRefinedEditorProbe)
-(void)sth_captureRefinedEditorProbe:(id)sender;
@end
@implementation UIResponder (STHRefinedEditorProbe)
-(void)sth_captureRefinedEditorProbe:(id)sender {capturedResponder=self;}
@end
@interface STHRefinedTransform:NSObject
@property CGAffineTransform original;
@property CGAffineTransform applied;
@property double sceneY;
@end
@implementation STHRefinedTransform
@end
static NSMapTable<UIView *,STHRefinedTransform *> *adjustments;
static __weak UIView *lastComposer;
static CADisplayLink *display;
static BOOL active;
static CFTimeInterval fastUntil,lastTick,lastReport;
static int lastStage;
extern BOOL STHMeasuredKeyboardRefined(UIWindowScene *,UIView *,CGRect *,double *);
static CGRect measuredCandidate;
static __weak UIWindowScene *measuredScene;
static CFTimeInterval measuredAt;
static BOOL haveMeasured;
static CGRect lastControlBounds;
static CFTimeInterval controlsStableAt;
static CFTimeInterval lastDetail;
static NSString *keyboardSource;
static BOOL shown(UIView *v){return v&&!v.hidden&&v.alpha>.01&&v.window;}
static BOOL keyboardWindow(UIWindow *w){return [NSStringFromClass(w.class) containsString:@"Keyboard"];}
static BOOL editing(UIView *v){return v&&([v isKindOfClass:UITextField.class]||[v isKindOfClass:UITextView.class]||[v conformsToProtocol:@protocol(UITextInput)]);}
static STHRect rr(CGRect r){return (STHRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
static void restoreView(UIView *v){
 STHRefinedTransform *s=[adjustments objectForKey:v];if(!s)return;
 if(CGAffineTransformEqualToTransform(v.transform,s.applied))
  [UIView performWithoutAnimation:^{v.transform=s.original;}];
 [adjustments removeObjectForKey:v];
}
static void restoreAll(void){for(UIView *v in adjustments.keyEnumerator.allObjects)restoreView(v);lastComposer=nil;}
static CGRect baseline(UIView *v,id<UICoordinateSpace> scene){
 STHRefinedTransform *s=[adjustments objectForKey:v];
 if(s&&!CGAffineTransformEqualToTransform(v.transform,s.applied)){
  [adjustments removeObjectForKey:v];s=nil; // app took ownership, do not restore stale transform
 }
 CGRect r=[v convertRect:v.bounds toCoordinateSpace:scene];
 for(UIView *a=v;a&&a!=v.window;a=a.superview){
  STHRefinedTransform *ours=[adjustments objectForKey:a];if(ours)r.origin.y-=ours.sceneY;
 }
 return r;
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
 [UIApplication.sharedApplication sendAction:@selector(sth_captureRefinedEditorProbe:) to:nil from:nil forEvent:nil];
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
 if(!shown(v)||depth>5||--*budget<0||v==root||[v isDescendantOfView:root])return;
 if(![root isDescendantOfView:v]){
  // An app emoji strip can itself be a collection/scroll view. Allow it as
  // an ATTACHED ROW, but the strict height/adjacency test below still excludes
  // the main conversation/comment scroll page and unrelated siblings.
  int b=150;if(rowEvidence(v,0,&b))[possible addObject:v];
 }
 for(UIView *c in v.subviews){if(*budget<=0)break;collectRows(c,root,depth+1,budget,possible);}
}
static unsigned protrudingCount;
static CGRect visibleRect(UIView *v,UIWindowScene *scene,BOOL unshifted){
 CGRect r=unshifted?baseline(v,scene.coordinateSpace):[v convertRect:v.bounds toCoordinateSpace:scene.coordinateSpace];
 for(UIView *a=v.superview;a&&a!=v.window;a=a.superview)if(a.clipsToBounds){
  CGRect clip=unshifted?baseline(a,scene.coordinateSpace):[a convertRect:a.bounds toCoordinateSpace:scene.coordinateSpace];
  r=CGRectIntersection(r,clip);if(CGRectIsNull(r)||CGRectIsEmpty(r))return CGRectNull;
 }
 return r;
}
static void protrusions(UIView *v,UIView *root,UIWindowScene *scene,int depth,int *budget,BOOL unshifted,CGRect *group){
 if(!shown(v)||depth>5||--*budget<0)return;
 if(v!=root){
  CGRect r=visibleRect(v,scene,unshifted);int b=100;
  if(!CGRectIsNull(r)&&STHRefinedRow(rr(*group),rr(r),scene.coordinateSpace.bounds.size.height,rowEvidence(v,0,&b),YES)){
   *group=CGRectUnion(*group,r);if(unshifted)protrudingCount++;
  }
 }
 for(UIView *c in v.subviews){if(*budget<=0)break;protrusions(c,root,scene,depth+1,budget,unshifted,group);}
}
static CGRect measuredGroup(NSArray<UIView *> *views,UIWindowScene *scene){
 CGRect result=CGRectNull;
 for(UIView *v in views){
  CGRect r=visibleRect(v,scene,NO);if(CGRectIsNull(r))continue;
  int b=500;protrusions(v,v,scene,0,&b,NO,&r);
  result=CGRectIsNull(result)?r:CGRectUnion(result,r);
 }
 return result;
}
static double priorAtBottom(NSArray<UIView *> *views,UIWindowScene *scene){
 CGFloat bottom=-CGFLOAT_MAX;double prior=0;
 for(UIView *v in views){
  CGRect r=visibleRect(v,scene,NO);if(CGRectIsNull(r))continue;
  int budget=500;protrusions(v,v,scene,0,&budget,NO,&r);
  if(CGRectGetMaxY(r)>bottom){
   bottom=CGRectGetMaxY(r);STHRefinedTransform *s=[adjustments objectForKey:v];prior=s?-s.sceneY:0;
  }
 }
 return prior;
}
static NSArray<UIView *> *assembly(UIView *root,UIWindowScene *scene,CGRect *bounds){
 CGRect group=baseline(root,scene.coordinateSpace);
 protrudingCount=0;int childBudget=600;
 // A panel can be inside an unclipped composer but extend below its bounds.
 // It moves with its ancestor: measure it, never apply a second child shift.
 for(int pass=0;pass<3;pass++){childBudget=600;protrusions(root,root,scene,0,&childBudget,YES,&group);}
 NSMutableArray<UIView *> *candidates=[NSMutableArray new],*result=[NSMutableArray arrayWithObject:root];
 // Up to3 bounded ancestor branches; never search a separate app/window for rows.
 UIView *ancestor=root.superview;
 for(int i=0;ancestor&&ancestor!=root.window&&i<4;i++,ancestor=ancestor.superview){
  int budget=600;collectRows(ancestor,root,0,&budget,candidates);
 }
 for(int pass=0;pass<4;pass++)for(UIView *row in candidates){
  BOOL overlapsTree=NO;
  for(UIView *used in result)if(row==used||[row isDescendantOfView:used]||[used isDescendantOfView:row]){overlapsTree=YES;break;}
  if(overlapsTree)continue;
  CGRect r=baseline(row,scene.coordinateSpace);int budget=100;
  if(STHRefinedRow(rr(group),rr(r),scene.coordinateSpace.bounds.size.height,rowEvidence(row,0,&budget),row.superview==root.superview||row.superview.superview==root.superview)){
   [result addObject:row];group=CGRectUnion(group,r);
  }
 }
 *bounds=group;return result;
}
// Detect only an objectively transparent tail below visible controls. The
// rectangle of a transparent reply wrapper is not the painted input edge.
static void controlsBounds(UIView *v,UIView *root,UIWindowScene *scene,int depth,int *budget,CGRect *out){
 if(!shown(v)||depth>6||--*budget<0)return;
 if(v!=root){
  BOOL image=[v isKindOfClass:UIImageView.class]&&((UIImageView *)v).image!=nil;
  BOOL control=[v isKindOfClass:UIControl.class]||editing(v)||image;
  CGRect r=visibleRect(v,scene,NO);
  if(control&&!CGRectIsNull(r)&&r.size.width>4&&r.size.height>4)
   *out=CGRectIsNull(*out)?r:CGRectUnion(*out,r);
 }
 for(UIView *c in v.subviews){if(*budget<=0)break;controlsBounds(c,root,scene,depth+1,budget,out);}
}
static BOOL transparent(UIView *v){
 UIColor *color=v.backgroundColor;CGColorRef layerColor=v.layer.backgroundColor;
 IMP draw=class_getMethodImplementation(v.class,@selector(drawRect:));
 IMP base=class_getMethodImplementation(UIView.class,@selector(drawRect:));
 // opaque is only a rendering hint; require absent fill/content/custom draw
 // rather than assuming every nil-background container is visually empty.
 return (!color||CGColorGetAlpha(color.CGColor)<.01)&&(!layerColor||CGColorGetAlpha(layerColor)<.01)&&
        draw==base&&!v.layer.contents&&!v.layer.mask&&v.layer.borderWidth==0;
}
static BOOL moveView(UIView *view,UIWindowScene *scene,double lift){
 STHRefinedTransform *s=[adjustments objectForKey:view];
 if(!s){s=[STHRefinedTransform new];s.original=view.transform;s.applied=view.transform;s.sceneY=0;[adjustments setObject:s forKey:view];}
 if(fabs(s.sceneY+lift)<.20)return NO;
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
@interface STHRefinedEditorGuard:NSObject
+(void)tick:(CADisplayLink *)link;
@end
@implementation STHRefinedEditorGuard
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
 CGRect measuredKeys;double measuredInset=0;keyboardSource=@"host-committed";
 if(STHMeasuredKeyboardRefined(scene,field,&measuredKeys,&measuredInset)){
  BOOL same=haveMeasured&&measuredScene==scene&&fabs(measuredKeys.origin.y-measuredCandidate.origin.y)<=.5&&
   fabs(measuredKeys.size.height-measuredCandidate.size.height)<=.5;
  if(!same){measuredCandidate=measuredKeys;measuredAt=now;haveMeasured=YES;measuredScene=scene;}
  // Use only repeated current samples. Do not permanently lock the first563
  // or warm590 source; no synthetic27pt compensation.
  else if(now-measuredAt>=.06){keys=measuredKeys;inset=measuredInset;keyboardSource=@"measured-excluding-app-accessory";}
 }else haveMeasured=NO;
 UIView *root=nil;
 for(UIView *v=field;v&&v!=window;v=v.superview){
  CGRect r=baseline(v,scene.coordinateSpace);
  if(r.size.height>fmin(240,scene.coordinateSpace.bounds.size.height*.34))break;
  if(STHCompactComposer(r.size.width,r.size.height,scene.coordinateSpace.bounds.size.width,
      scene.coordinateSpace.bounds.size.height,[v isKindOfClass:UIScrollView.class])){root=v;break;}
 }
 if(!root||!root.superview){restoreAll();report(3,[field convertRect:field.bounds toCoordinateSpace:scene.coordinateSpace],keys.origin.y,0,0);return;}
 if(lastComposer!=root){restoreAll();lastComposer=root;controlsStableAt=now;lastControlBounds=CGRectNull;}
 CGRect original;NSArray<UIView *> *views=assembly(root,scene,&original);
 // A removed/reparented toolbar must not retain an old transform.
 for(UIView *old in adjustments.keyEnumerator.allObjects)if(![views containsObject:old])restoreView(old);
 CGRect actual=measuredGroup(views,scene);
 if(CGRectIsNull(actual)||CGRectIsEmpty(actual))return;
 STHRefinedTransform *current=[adjustments objectForKey:root];double prior=current?-current.sceneY:0;
 double lift=STHRefinedLift(fmax(0,priorAtBottom(views,scene)),CGRectGetMaxY(actual),keys.origin.y,original.origin.y,
     original.size.height,scene.coordinateSpace.bounds.size.height);
 // Only the reported transparent-tail app opts into DOWNWARD visual-edge
 // correction. Other apps preserve all intentional native bottom spacing.
 BOOL closeTail=STHProfileForBundle(NSBundle.mainBundle.bundleIdentifier.UTF8String)==STHEditorTransparentTail;
 CGRect controls=CGRectNull;int controlBudget=900;
 controlsBounds(root,root,scene,0,&controlBudget,&controls);
 if(closeTail&&!CGRectIsNull(controls)&&views.count==1&&protrudingCount==0){
  BOOL steady=!CGRectIsNull(lastControlBounds)&&fabs(controls.origin.y-lastControlBounds.origin.y)<.6&&
    fabs(CGRectGetMaxY(controls)-CGRectGetMaxY(lastControlBounds))<.6;
  if(!steady){controlsStableAt=now;lastControlBounds=controls;}
  double drop=STHTransparentTailDrop(CGRectGetMaxY(actual),CGRectGetMaxY(controls),keys.origin.y,
      actual.size.height,transparent(root),steady&&now-controlsStableAt>=.12);
  if(drop>0)lift=prior-drop;
  // Once a measured transparent tail is collapsed, use the visible controls
  // as the lower edge. Do not alternate between wrapper and controls.
  else if(prior<0&&transparent(root)){
   double tail=CGRectGetMaxY(actual)-CGRectGetMaxY(controls);
   if(tail>=1&&tail<=fmin(44,actual.size.height*.35)){
    double desired=prior+CGRectGetMaxY(controls)-keys.origin.y;
    lift=fmax(-tail,fmin(0,desired));
   }
  }
 }
 BOOL changed=NO;
 if(!adjustments)adjustments=[NSMapTable weakToStrongObjectsMapTable];
 for(UIView *v in views){if(v.superview)changed=moveView(v,scene,lift)||changed;}
 CGRect measured=measuredGroup(views,scene);
 unsigned rows=(unsigned)views.count-1+protrudingCount;
 report(changed?5:4,measured,keys.origin.y,lift,rows);
 if(changed||now-lastDetail>=.75){lastDetail=now;
  unsigned flags=(transparent(root)?1u:0u)|(protrudingCount?2u:0u)|([keyboardSource hasPrefix:@"measured"]?4u:0u)|(closeTail?8u:0u);
  if(!CGRectIsNull(controls))STHReportEditor(NSBundle.mainBundle.bundleIdentifier,7,controls,keys.origin.y,lift,flags);
  STHWriteLayoutLog([NSString stringWithFormat:@"refined-editor class=%@ field=%@ root=%@ actual=%@ controls=%@ result=%@ keysTop=%.3f source=%@ shift=%.3f rows=%u transparent=%d",
   NSStringFromClass(root.class),NSStringFromClass(field.class),NSStringFromCGRect(original),NSStringFromCGRect(actual),
   NSStringFromCGRect(controls),NSStringFromCGRect(measured),keys.origin.y,keyboardSource,lift,rows,transparent(root)]);
 }
}
@end
void STHEditorVisibilityRefinedEvent(BOOL showing){
 if(![NSThread isMainThread])return;
 if(!showing){active=NO;haveMeasured=NO;measuredScene=nil;[display invalidate];display=nil;restoreAll();report(6,CGRectZero,0,0,0);return;}
 if(!active){active=YES;lastTick=0;report(1,CGRectZero,0,0,0);}
 fastUntil=CACurrentMediaTime()+1.2;
 if(!display){display=[CADisplayLink displayLinkWithTarget:STHRefinedEditorGuard.class selector:@selector(tick:)];
  display.preferredFramesPerSecond=30;[display addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];}
}
static id focusFieldObserver,focusTextObserver;
__attribute__((constructor)) static void editorGuardReady(void){
 extern BOOL STHRefinementEnabled(void);if(!STHRefinementEnabled())return;
 extern BOOL STHCompositeEnabled(void);if(STHCompositeEnabled())return;
 dispatch_async(dispatch_get_main_queue(),^{
  void(^focus)(NSNotification *)=^(NSNotification *note){
   if(STHLayoutStatus(NSBundle.mainBundle.bundleIdentifier)>0)STHEditorVisibilityRefinedEvent(YES);
  };
  focusFieldObserver=[NSNotificationCenter.defaultCenter addObserverForName:UITextFieldTextDidBeginEditingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:focus];
  focusTextObserver=[NSNotificationCenter.defaultCenter addObserverForName:UITextViewTextDidBeginEditingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:focus];
 });
}
