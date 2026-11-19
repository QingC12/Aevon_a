// The PRODUCTION CompositeStructure.inc runs against a geometry-only host
// view model. This tests hook ordering and ownership, NOT private iPhone UI.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <assert.h>
#import "EditorCompositeMath.h"
@class UIWindow;
@interface UIView:NSObject
@property(nonatomic,weak) UIView *superview;
@property(nonatomic,strong) NSMutableArray<UIView *> *subviews;
@property(nonatomic) CGRect rect;
@property(nonatomic) CGRect bounds;
@property(nonatomic) CGRect frame;
@property(nonatomic) CGPoint center;
@property(nonatomic) BOOL lastSetterSawOriginal;
@property(nonatomic) CGAffineTransform transform;
@property(nonatomic) BOOL hidden;
@property(nonatomic) double alpha;
@property(nonatomic,strong) NSArray *gestureRecognizers;
@property(nonatomic) BOOL editor;
@property(nonatomic,readonly) UIWindow *window;
-(BOOL)isDescendantOfView:(UIView *)view;
-(CGRect)convertRect:(CGRect)rect toCoordinateSpace:(id)space;
-(void)layoutSubviews;
+(void)performWithoutAnimation:(void(^)(void))block;
@end
@interface UIWindow:UIView @end
@interface UIScrollView:UIView @end
@interface UIControl:UIView @end
@interface UILabel:UIView @end
@interface UIImageView:UIView @end
@interface TestSpace:NSObject
@property CGRect bounds;
@end
@implementation TestSpace @end
@interface UIWindowScene:NSObject
@property(nonatomic,strong) TestSpace *coordinateSpace;
@end
@implementation UIWindowScene @end
@implementation UIView
-(instancetype)init{if((self=[super init])){_subviews=[NSMutableArray new];_alpha=1;_transform=CGAffineTransformIdentity;_gestureRecognizers=@[];}return self;}
-(CGRect)bounds{return CGRectMake(0,0,self.rect.size.width,self.rect.size.height);}
-(void)setBounds:(CGRect)b{self.lastSetterSawOriginal=CGAffineTransformIsIdentity(self.transform);CGRect r=self.rect;r.size=b.size;self.rect=r;}
-(CGRect)frame{return CGRectOffset(self.rect,self.transform.tx,self.transform.ty);}
-(void)setFrame:(CGRect)f{self.lastSetterSawOriginal=CGAffineTransformIsIdentity(self.transform);self.rect=CGRectOffset(f,-self.transform.tx,-self.transform.ty);}
-(CGPoint)center{return CGPointMake(CGRectGetMidX(self.rect),CGRectGetMidY(self.rect));}
-(void)setCenter:(CGPoint)p{self.lastSetterSawOriginal=CGAffineTransformIsIdentity(self.transform);CGRect r=self.rect;r.origin=CGPointMake(p.x-r.size.width*.5,p.y-r.size.height*.5);self.rect=r;}
-(UIWindow *)window{if([self isKindOfClass:UIWindow.class])return (UIWindow *)self;return self.superview.window;}
-(BOOL)isDescendantOfView:(UIView *)view{for(UIView *v=self;v;v=v.superview)if(v==view)return YES;return NO;}
-(CGRect)convertRect:(CGRect)rect toCoordinateSpace:(id)space{
 CGRect r=self.rect;for(UIView *v=self;v;v=v.superview){r.origin.x+=v.transform.tx;r.origin.y+=v.transform.ty;}return r;
}
-(void)layoutSubviews{}
+(void)performWithoutAnimation:(void(^)(void))block{block();}
@end
@implementation UIWindow @end
@implementation UIScrollView @end
@implementation UIControl @end
@implementation UILabel @end
@implementation UIImageView @end
@interface STHCompositeTransform:NSObject
@property CGAffineTransform original;
@property CGAffineTransform applied;
@property double sceneY;
@end
@implementation STHCompositeTransform @end
static NSMapTable<UIView *,STHCompositeTransform *> *adjustments;
static BOOL active=YES;
static BOOL shown(UIView *v){return v&&!v.hidden&&v.alpha>.01&&v.window;}
static BOOL editing(UIView *v){return v.editor;}
static STHRect rr(CGRect r){return(STHRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
static CGRect baseline(UIView *v,id scene){return v.rect;}
#include "CompositeStructure.inc"
@interface NativeParent:UIView
@property(nonatomic,weak) UIView *target;
@property(nonatomic) BOOL sawOriginal;
@property(nonatomic) BOOL independentChange;
@property(nonatomic) BOOL closeDuringLayout;
@property(nonatomic) int calls;
@end
@implementation NativeParent
-(void)layoutSubviews{
 self.calls++;self.sawOriginal=CGAffineTransformIsIdentity(self.target.transform);
 if(self.independentChange)self.target.transform=CGAffineTransformMakeScale(1.2,1.2);
 if(self.closeDuringLayout){active=NO;[adjustments removeAllObjects];[layoutAncestors removeAllObjects];}
 [super layoutSubviews];
}
@end
static void add(UIView *p,UIView *c,CGRect rect){c.superview=p;c.rect=rect;[p.subviews addObject:c];}
int main(void){@autoreleasepool{
 UIWindow *window=[UIWindow new];window.rect=CGRectMake(0,0,430,731);
 NativeParent *parent=[NativeParent new];add(window,parent,window.rect);
 UIView *owner=[UIView new];add(parent,owner,CGRectMake(0,330,430,175));parent.target=owner;
 UIView *textWrapper=[UIView new];add(owner,textWrapper,CGRectMake(16,357,398,82.625));
 UIView *field=[UIView new];field.editor=YES;add(textWrapper,field,CGRectMake(24,370,382,20));
 UIControl *tools=[UIControl new];add(owner,tools,CGRectMake(0,450,430,50));
 UIWindowScene *scene=[UIWindowScene new];scene.coordinateSpace=[TestSpace new];scene.coordinateSpace.bounds=window.rect;
 assert(composerOwner(field,window,scene)==owner);
 adjustments=[NSMapTable weakToStrongObjectsMapTable];
 STHCompositeTransform *state=[STHCompositeTransform new];state.original=CGAffineTransformIdentity;
 state.applied=CGAffineTransformMakeTranslation(0,-17);state.sceneY=-17;
 [adjustments setObject:state forKey:owner];owner.transform=state.applied;
 installNeutralLayout(owner);
 for(int i=0;i<100;i++){
  [parent layoutSubviews];assert(parent.sawOriginal);
  assert(CGAffineTransformEqualToTransform(owner.transform,state.applied));
 }
 // Production setters run at native transform, not only layoutSubviews.
 for(int cycle=0;cycle<100;cycle++){
  owner.frame=CGRectMake(0,330,430,175);
  assert(owner.lastSetterSawOriginal&&owner.rect.origin.y==330);
  owner.bounds=CGRectMake(0,0,430,175);assert(owner.lastSetterSawOriginal);
  owner.center=CGPointMake(215,417.5);assert(owner.lastSetterSawOriginal);
  assert(owner.rect.origin.y==330&&CGAffineTransformEqualToTransform(owner.transform,state.applied));
 }
 NativeParent *unrelated=[NativeParent new];UIView *unrelatedChild=[UIView new];
 unrelated.target=unrelatedChild;unrelatedChild.transform=CGAffineTransformMakeTranslation(0,-9);
 unrelatedChild.frame=CGRectMake(0,100,430,40);
 assert(!unrelatedChild.lastSetterSawOriginal); // unselected instance never neutralized
 [unrelated layoutSubviews];assert(!unrelated.sawOriginal&&unrelatedChild.transform.ty==-9);
 parent.independentChange=YES;[parent layoutSubviews];
 assert([adjustments objectForKey:owner]==nil&&owner.transform.a==1.2);
 assert(neutralLayoutDepth==0);
 parent.independentChange=NO;owner.transform=state.applied;
 [adjustments setObject:state forKey:owner];installNeutralLayout(owner);
 parent.closeDuringLayout=YES;[parent layoutSubviews];
 assert(!active&&CGAffineTransformIsIdentity(owner.transform)&&[adjustments objectForKey:owner]==nil);
 puts("Production geometry shield passed100 native relayouts and100 frame/bounds/center setters, complete175pt owner, unrelated-instance passthrough and independent app transform wins");
}return 0;}
