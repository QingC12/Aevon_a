// Only the3 remaining app profiles. No change to QQ/Minis/WeChat measurement.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import "LayoutBus.h"
#import "KeyboardPlaneMath.h"
static STHRect rr(CGRect r){return(STHRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
static BOOL excludes(UIView *v,NSArray<UIView *> *appRows,BOOL wrapper){
 for(UIView *a in appRows)
  if(v==a||[v isDescendantOfView:a]||(wrapper&&[a isDescendantOfView:v]))return YES;
 return NO;
}
static void plane(UIView *v,UIScreen *s,CGRect physical,CGRect host,NSArray *appRows,
 int depth,int *budget,CGRect *best,int *quality){
 if(!v||v.hidden||v.alpha<.01||depth>20||--*budget<0||excludes(v,appRows,NO))return;
 NSString *n=NSStringFromClass(v.class),*bundle=[NSBundle bundleForClass:v.class].bundleIdentifier;
 int confidence=[n containsString:@"UIKBKeyplaneView"]?3:
  (([n containsString:@"UIKeyboardLayoutStar"]||[n containsString:@"UIKeyboardLayoutView"])?2:0);
 if(confidence&&[bundle hasPrefix:@"com.apple."]&&!excludes(v,appRows,YES)){
  CGRect r=[v convertRect:v.bounds toCoordinateSpace:s.fixedCoordinateSpace];
  if(STHSelectKeyboardPlane(rr(r),confidence,rr(host),rr(physical),*quality,rr(*best))){*best=r;*quality=confidence;}
 }
 for(UIView *c in v.subviews){if(*budget<=0)break;plane(c,s,physical,host,appRows,depth+1,budget,best,quality);}
}
static void assistantRows(UIView *v,UIScreen *s,CGRect physical,NSArray *appRows,int depth,int *budget,CGRect *keys){
 if(!v||v.hidden||v.alpha<.01||depth>20||--*budget<0||excludes(v,appRows,NO))return;
 NSString *name=NSStringFromClass(v.class).lowercaseString;
 BOOL system=[[NSBundle bundleForClass:v.class].bundleIdentifier hasPrefix:@"com.apple."];
 BOOL role=[name containsString:@"candidate"]||[name containsString:@"prediction"]||
   [name containsString:@"quicktype"]||[name containsString:@"inputassistant"]||
   [name containsString:@"keyboardtoolbar"];
 CGRect r=[v convertRect:v.bounds toCoordinateSpace:s.fixedCoordinateSpace];
 if(STHKeyboardConnectedRow(rr(*keys),rr(r),rr(physical),system&&role,excludes(v,appRows,YES)))*keys=CGRectUnion(*keys,r);
 for(UIView *c in v.subviews){if(*budget<=0)break;assistantRows(c,s,physical,appRows,depth+1,budget,keys);}
}
BOOL STHMeasuredKeyboardComposite(UIWindowScene *scene,UIView *field,CGRect *mapped,double *inset){
 if(!NSThread.isMainThread||!scene||!field)return NO;
 UIScreen *s=scene.screen;double scale=s.nativeScale;if(scale<=0)return NO;
 CGRect physical=CGRectMake(0,0,s.nativeBounds.size.width/scale,s.nativeBounds.size.height/scale),host;
 if(!STHReadPhysicalLayout(NSBundle.mainBundle.bundleIdentifier,NULL,&host))return NO;
 NSMutableArray<UIView *> *appRows=[NSMutableArray new];
 UIResponder *r=field;
 for(int depth=0;r&&r!=field.window&&depth<20;depth++,r=r.nextResponder){
  UIView *a=r.inputAccessoryView;
  if(a.window&&!a.hidden&&a.alpha>.01&&![appRows containsObject:a])[appRows addObject:a];
 }
 NSMutableArray<UIWindow *> *windows=[NSMutableArray new];
 Class cls=NSClassFromString(@"UIRemoteKeyboardWindow");SEL sel=NSSelectorFromString(@"remoteKeyboardWindowForScreen:create:");
 if([cls respondsToSelector:sel]){
  id w=((id(*)(id,SEL,UIScreen *,BOOL))objc_msgSend)(cls,sel,s,NO);
  if([w isKindOfClass:UIWindow.class])[windows addObject:w];
 }
 for(UIWindow *w in UIApplication.sharedApplication.windows)
  if(w.screen==s&&[NSStringFromClass(w.class) containsString:@"Keyboard"]&&![windows containsObject:w])[windows addObject:w];
 CGRect keys=host;int quality=0;
 for(UIWindow *w in windows){int budget=1100;plane(w,s,physical,host,appRows,0,&budget,&keys,&quality);}
 // InputSetHost/Container/Placeholder and UIKeyboardImpl are NEVER trusted
 // as a substitute keyplane. In the log these added the app's57/61pt row.
 for(int pass=0;pass<3;pass++)for(UIWindow *w in windows){int budget=700;assistantRows(w,s,physical,appRows,0,&budget,&keys);}
 if(quality==0&&CGRectEqualToRect(keys,host))return NO; // keep host path, do not label it a local measurement

 return STHReadLayoutUsingKeyboard(NSBundle.mainBundle.bundleIdentifier,scene.coordinateSpace.bounds,keys,mapped,inset);
}
