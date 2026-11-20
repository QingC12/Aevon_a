#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "Chooser.h"
#import "ChooserPanel.h"
#import "ChooserMotion.h"
extern UIImage *STHAppChooserIcon(CGFloat);
extern BOOL STHSystemActionsEnabled(void);
extern BOOL STHSystemActionDismissRingNative(void);
extern BOOL STHSystemActionHideQuickSettingNative(void);
@interface STHChooserPassthrough:UIView
@end
@implementation STHChooserPassthrough
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event{
 UIView *hit=[super hitTest:point withEvent:event];return hit==self?nil:hit;
}
@end
@interface STHCenterChooser:NSObject
@property(nonatomic,strong) CADisplayLink *display;
@property(nonatomic,strong) STHChooserPassthrough *overlay;
@property(nonatomic,strong) UIButton *button;
@property(nonatomic,weak) UIView *host;
@property(nonatomic,strong) STHChooserPanel *panel;
@property(nonatomic) CFTimeInterval lastTick,lastScan,suppressUntil,hideStart;
@property(nonatomic) double hideFrom,previousTarget;
@property(nonatomic) BOOL wasAvailable;
@end
@implementation STHCenterChooser{
 STHChooserSpring _scale,_x,_y;
}
static BOOL isHost(UIView *view){
 NSString *name=NSStringFromClass(view.class);
 return [name containsString:@"HostingView"]&&([name containsString:@"Stheno.Container"]||[name containsString:@"6Stheno9Container"]||[name isEqualToString:@"_UIHostingView<Container>"]);
}
static UIView *locate(UIView *view,int depth,int *budget){
 if(!view||view.hidden||view.alpha<.01||depth>12||--*budget<0)return nil;
 if(isHost(view))return view;
 for(UIView *child in view.subviews){UIView *found=locate(child,depth+1,budget);if(found)return found;}
 return nil;
}
- (instancetype)init{
 if((self=[super init])){
  _overlay=[[STHChooserPassthrough alloc] initWithFrame:CGRectZero];_overlay.backgroundColor=UIColor.clearColor;_overlay.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
  _button=[UIButton buttonWithType:UIButtonTypeCustom];_button.backgroundColor=[UIColor colorWithWhite:.85 alpha:.42];_button.clipsToBounds=NO;
  [_button setImage:STHAppChooserIcon(UIScreen.mainScreen.scale) forState:UIControlStateNormal];_button.imageView.contentMode=UIViewContentModeScaleAspectFit;
  _button.accessibilityLabel=@"选择其他应用";_button.accessibilityHint=@"搜索尚未加入圆盘的应用并以浮窗打开";
  [_button addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
  [_button addTarget:self action:@selector(press) forControlEvents:UIControlEventTouchDown];
  [_button addTarget:self action:@selector(releasePress) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
  [_overlay addSubview:_button];_overlay.hidden=YES;
  _display=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];_display.preferredFramesPerSecond=12;[_display addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(suspend) name:UIApplicationWillResignActiveNotification object:nil];
 }
 return self;
}
- (void)findHost:(CFTimeInterval)now{
 if(self.host.window&&!self.host.hidden&&!self.host.window.hidden)return;
 if(now-self.lastScan<.7)return;self.lastScan=now;
 NSMutableArray<UIWindow *> *windows=[NSMutableArray array];
 for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class])for(UIWindow *window in ((UIWindowScene *)scene).windows)if(!window.hidden&&window.alpha>.01)[windows addObject:window];
 for(UIWindow *window in windows){int budget=160;UIView *host=locate(window,0,&budget);if(!host)continue;
  self.host=host;[self.overlay removeFromSuperview];self.overlay.frame=window.bounds;[window addSubview:self.overlay];return;
 }
 self.host=nil;self.overlay.hidden=YES;
}
- (void)tick:(CADisplayLink *)link{
 CFTimeInterval now=CACurrentMediaTime();double dt=self.lastTick?now-self.lastTick:1./30;self.lastTick=now;
 STHChooserRingSnapshot snapshot={0};BOOL ready=STHSystemActionsEnabled()&&STHChooserReadRing(&snapshot);
 [self findHost:now];
 BOOL blocked=!ready||!self.host.window||self.host.window.hidden||snapshot.editing||snapshot.quickSetting||snapshot.showTab||now<self.suppressUntil;
 double target=blocked?0:snapshot.scale;BOOL available=!blocked&&target>.5;
 if(!available&&self.panel)[self.panel dismissChoosing:nil animated:YES];
 self.display.preferredFramesPerSecond=(target>.01||_scale.x>.01||self.panel)?30:12;
 self.button.userInteractionEnabled=available&&!self.panel;
 if(target<=.001&&self.previousTarget>.001){self.hideStart=now;self.hideFrom=_scale.x;}
 if(target<=.001){double t=MIN(1,MAX(0,(now-self.hideStart)/.15));_scale.x=self.hideFrom*(1-t*t);_scale.v=0;}
 else if(UIAccessibilityIsReduceMotionEnabled()){_scale.x=target;_scale.v=0;}
 else STHChooserSpringStep(&_scale,target,dt,snapshot.damping);
 self.previousTarget=target;
 if(ready){
  CGPoint fixed=CGPointMake(snapshot.portraitX+snapshot.offsetX,snapshot.portraitY+snapshot.offsetY);
  CGPoint point=[self.overlay convertPoint:fixed fromCoordinateSpace:UIScreen.mainScreen.fixedCoordinateSpace];
  if(!self.wasAvailable||snapshot.gestureState<2||UIAccessibilityIsReduceMotionEnabled()){
   _x=(STHChooserSpring){point.x,0};_y=(STHChooserSpring){point.y,0};
  }else{STHChooserSpringStep(&_x,point.x,dt,snapshot.damping);STHChooserSpringStep(&_y,point.y,dt,snapshot.damping);}
  double diameter=STHChooserDiameter(snapshot.radius,snapshot.iconWidth);
  self.button.bounds=CGRectMake(0,0,diameter,diameter);self.button.layer.cornerRadius=diameter/2;
  self.button.imageEdgeInsets=UIEdgeInsetsMake(diameter*.15,diameter*.15,diameter*.15,diameter*.15);
  self.button.center=CGPointMake(_x.x,_y.x);
  self.button.transform=CGAffineTransformMakeScale(MAX(.001,_scale.x),MAX(.001,_scale.x));
  self.button.alpha=STHChooserAlpha(_scale.x);
  self.overlay.hidden=diameter<20||self.button.alpha<.005;
 }else self.overlay.hidden=YES;
 self.wasAvailable=available;
 (void)link;
}
- (void)press{[UIView animateWithDuration:.10 animations:^{self.button.imageView.transform=CGAffineTransformMakeScale(.9,.9);}];}
- (void)releasePress{[UIView animateWithDuration:.2 delay:0 usingSpringWithDamping:.75 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{self.button.imageView.transform=CGAffineTransformIdentity;} completion:nil];}
- (void)open{
 if(self.panel||self.overlay.hidden)return;
 STHChooserPanel *panel=[STHChooserPanel new];panel.items=STHChooserSnapshotUnpinned();self.panel=panel;
 __weak typeof(self) weak=self;
 panel.closed=^(NSString *identifier){
  typeof(self) strong=weak;if(!strong)return;strong.panel=nil;
  if(identifier.length){
   STHSystemActionDismissRingNative();STHSystemActionHideQuickSettingNative();
   if(!STHChooserSubmitFloating(identifier))UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"应用状态已变化，请重新打开选择器");
  }
 };
 CGPoint origin=[self.overlay convertPoint:self.button.center toCoordinateSpace:UIScreen.mainScreen.coordinateSpace];
 [panel showFromPoint:origin inScene:self.host.window.windowScene aboveLevel:self.host.window.windowLevel];
}
- (void)suspend{[self.panel dismissChoosing:nil animated:NO];self.button.userInteractionEnabled=NO;}
@end
static STHCenterChooser *center;
void STHInstallCenterChooser(void){
 dispatch_async(dispatch_get_main_queue(),^{if(!center)center=[STHCenterChooser new];});
}
void STHChooserHideBeforeCapture(void){
 center.suppressUntil=CACurrentMediaTime()+1;center.overlay.hidden=YES;
 [center.panel dismissChoosing:nil animated:NO];
}
