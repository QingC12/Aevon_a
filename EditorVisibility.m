// App-side, currently focused editor ONLY. No input strings are read. This
// supplements geometric insets for app-owned controls below an input field.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "LayoutBus.h"
#import "EditorVisibilityMath.h"
static __weak UIView *composer;
static CGAffineTransform originalTransform,appliedTransform;
static double appliedSceneY;
static CADisplayLink *editorDisplayLink;
static CFTimeInterval deadline,lastLog;
static BOOL active,haveTransform;
static NSMapTable<UIView *,NSValue *> *rowOriginals,*rowApplied;
static NSMutableArray<UIView *> *attachedRows;
extern UIWindow *STHTargetKeyboardWindow(UIWindowScene *,UIWindow *);
static BOOL visible(UIView *v){return v&&!v.hidden&&v.alpha>.01&&v.window;}
static UIView *findResponder(UIView *v,int depth,int *budget){
 if(!visible(v)||depth>20||--*budget<0)return nil;
 if(v.isFirstResponder)return v;
 for(UIView *child in v.subviews){if(*budget<=0)break;UIView *found=findResponder(child,depth+1,budget);if(found)return found;}
 return nil;
}
static BOOL editable(UIView *v){return [v isKindOfClass:UITextField.class]||[v isKindOfClass:UITextView.class]||[v conformsToProtocol:@protocol(UITextInput)];}
static void restore(void){
 for(UIView *row in rowOriginals){
  NSValue *applied=[rowApplied objectForKey:row];
  if(applied&&CGAffineTransformEqualToTransform(row.transform,applied.CGAffineTransformValue))row.transform=[rowOriginals objectForKey:row].CGAffineTransformValue;
 }
 rowOriginals=nil;rowApplied=nil;attachedRows=nil;
 UIView *v=composer;
 if(v&&haveTransform&&CGAffineTransformEqualToTransform(v.transform,appliedTransform))v.transform=originalTransform;
 composer=nil;haveTransform=NO;appliedSceneY=0;
}
static BOOL panel(UIView *v){
 NSString *n=NSStringFromClass(v.class).lowercaseString;
 return [n containsString:@"toolbar"]||[n containsString:@"emoji"]||[n containsString:@"emoticon"]||
        [n containsString:@"emotion"]||[n containsString:@"inputaccessory"];
}
static CGRect assemblyFrame(UIView *root,id<UICoordinateSpace> scene){
 attachedRows=[NSMutableArray new];
 CGRect r=[root convertRect:root.bounds toCoordinateSpace:scene];
 // Include only visibly attached sibling rows, independent of visitation order.
 // They remain APP UI, never reclassified as keyboard height.
 for(int pass=0;pass<3;pass++)for(UIView *v in root.superview.subviews){
  if(v==root||!visible(v)||!panel(v))continue;
  CGRect p=[v convertRect:v.bounds toCoordinateSpace:scene];
  if(p.size.width>=r.size.width*.65&&p.size.height>=8&&p.size.height<=160&&
     p.origin.y>=r.origin.y&&p.origin.y<=CGRectGetMaxY(r)+4){
   r=CGRectUnion(r,p);if(![attachedRows containsObject:v])[attachedRows addObject:v];
  }
 }
 return r;
}
@interface STHEditorGuard:NSObject
+(void)tick:(CADisplayLink *)sender;
@end
@implementation STHEditorGuard
+(void)tick:(CADisplayLink *)sender {
 if(!active||CACurrentMediaTime()>deadline){[editorDisplayLink invalidate];editorDisplayLink=nil;return;}
 for(UIScene *s in UIApplication.sharedApplication.connectedScenes){
  if(![s isKindOfClass:UIWindowScene.class])continue;UIWindowScene *scene=(UIWindowScene *)s;
  if(STHLayoutStatus(NSBundle.mainBundle.bundleIdentifier)!=1)continue;
  UIWindow *w=STHTargetKeyboardWindow(scene,nil);if(!w)continue;
  int budget=1400;UIView *field=findResponder(w,0,&budget);if(!editable(field))continue;
  // Choose a bounded app-owned ancestor around the textfield and its control
  // rows, never a window, scroll-content page, or the entire comment popup.
  UIView *candidate=nil;
  for(UIView *v=field;v&&v!=w;v=v.superview){
   CGRect r=[v convertRect:v.bounds toCoordinateSpace:scene.coordinateSpace];
   if(r.size.height>fmin(300.0,scene.coordinateSpace.bounds.size.height*.45))break;
   if(![v isKindOfClass:UIScrollView.class]&&r.size.width>=w.bounds.size.width*.60&&r.size.height>=24)candidate=v;
  }
  if(!candidate||!candidate.superview)continue;
  if(composer!=candidate){restore();composer=candidate;}
  if(haveTransform&&!CGAffineTransformEqualToTransform(candidate.transform,appliedTransform)){
   // Respect an app's own ongoing transform/layout; don't fight it this frame.
   haveTransform=NO;appliedSceneY=0;
  }
  CGRect mapped;double inset=0;
  if(!STHReadLayout(NSBundle.mainBundle.bundleIdentifier,scene.coordinateSpace.bounds,&mapped,&inset))continue;
  CGRect r=assemblyFrame(candidate,scene.coordinateSpace);
  double baselineTop=r.origin.y-appliedSceneY,baselineBottom=CGRectGetMaxY(r)-appliedSceneY;
  double lift=STHComposerLift(baselineTop,baselineBottom,mapped.origin.y,scene.coordinateSpace.bounds.size.height);
  if(fabs(-lift-appliedSceneY)<.75)continue;
  if(!haveTransform){originalTransform=candidate.transform;haveTransform=YES;}
  CGPoint zero=[candidate.superview convertPoint:CGPointZero fromCoordinateSpace:scene.coordinateSpace];
  CGPoint shifted=[candidate.superview convertPoint:CGPointMake(0,-lift) fromCoordinateSpace:scene.coordinateSpace];
  CGAffineTransform t=originalTransform;t.tx+=shifted.x-zero.x;t.ty+=shifted.y-zero.y;
  appliedTransform=t;appliedSceneY=-lift;
  // Follow the current target without restarting a second keyboard animation.
  [UIView performWithoutAnimation:^{candidate.transform=t;}];
  if(!rowOriginals){rowOriginals=[NSMapTable weakToStrongObjectsMapTable];rowApplied=[NSMapTable weakToStrongObjectsMapTable];}
  for(UIView *row in attachedRows){
   NSValue *old=[rowOriginals objectForKey:row],*our=[rowApplied objectForKey:row];
   if(!old||!our||!CGAffineTransformEqualToTransform(row.transform,our.CGAffineTransformValue)){
    old=[NSValue valueWithCGAffineTransform:row.transform];[rowOriginals setObject:old forKey:row];
   }
   CGPoint a=[row.superview convertPoint:CGPointZero fromCoordinateSpace:scene.coordinateSpace];
   CGPoint b=[row.superview convertPoint:CGPointMake(0,-lift) fromCoordinateSpace:scene.coordinateSpace];
   CGAffineTransform rt=old.CGAffineTransformValue;rt.tx+=b.x-a.x;rt.ty+=b.y-a.y;
   [UIView performWithoutAnimation:^{row.transform=rt;}];
   [rowApplied setObject:[NSValue valueWithCGAffineTransform:rt] forKey:row];
  }
  if(CACurrentMediaTime()-lastLog>.2){lastLog=CACurrentMediaTime();
   STHWriteLayoutLog([NSString stringWithFormat:@"editor-visibility class=%@ baseline={%.3f,%.3f} keysTop=%.3f lift=%.3f includes-app-rows=1",NSStringFromClass(candidate.class),baselineTop,baselineBottom,mapped.origin.y,lift]);
  }
  return;
 }
}
@end
void STHEditorVisibilityEvent(BOOL showing){
 if(![NSThread isMainThread])return;
 if(!showing){active=NO;[editorDisplayLink invalidate];editorDisplayLink=nil;restore();return;}
 active=YES;deadline=CACurrentMediaTime()+1.2;
 if(!editorDisplayLink){editorDisplayLink=[CADisplayLink displayLinkWithTarget:STHEditorGuard.class selector:@selector(tick:)];
  editorDisplayLink.preferredFramesPerSecond=30;[editorDisplayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];}
}
