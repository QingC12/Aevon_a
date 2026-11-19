// Read only class/bounds/visibility of keyboard-owned views. Never keys or text.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "LayoutBus.h"
static BOOL docked(CGRect r,CGRect screen){return isfinite(r.origin.x)&&isfinite(r.origin.y)&&
 isfinite(r.size.width)&&isfinite(r.size.height)&&r.size.width>=screen.size.width*.7&&r.size.height>=60&&
 r.size.height<screen.size.height*.7&&fabs(CGRectGetMaxY(r)-CGRectGetMaxY(screen))<=6;}
static void hosts(UIView *v,UIScreen *screen,CGRect physical,int depth,int *budget,CGRect *out){
 if(!v||v.hidden||v.alpha<.01||depth>18||--*budget<0)return;
 NSString *n=NSStringFromClass(v.class);
 if([n containsString:@"InputSetHost"]||[n containsString:@"RemoteKeyboardPlaceholder"]||[n containsString:@"InputSetContainer"]){
  CGRect r=[v convertRect:v.bounds toCoordinateSpace:screen.fixedCoordinateSpace];
  if(docked(r,physical))*out=CGRectIsNull(*out)?r:CGRectUnion(*out,r);
 }
 for(UIView *c in v.subviews){if(*budget<=0)break;hosts(c,screen,physical,depth+1,budget,out);}
}
static void rows(UIView *v,UIScreen *screen,CGRect physical,int depth,int *budget,CGRect *out){
 if(!v||v.hidden||v.alpha<.01||depth>18||--*budget<0)return;
 NSString *n=NSStringFromClass(v.class).lowercaseString;
 NSString *owner=[NSBundle bundleForClass:v.class].bundleIdentifier;
 BOOL systemOwned=[owner hasPrefix:@"com.apple."];
 if(systemOwned&&([n containsString:@"accessory"]||[n containsString:@"assistant"]||[n containsString:@"candidate"]||[n containsString:@"prediction"]||[n containsString:@"toolbar"])) {
  CGRect r=[v convertRect:v.bounds toCoordinateSpace:screen.fixedCoordinateSpace];
  if(r.size.width>=physical.size.width*.7&&r.size.height>=8&&r.size.height<=160&&r.origin.y>=0&&
    r.origin.y<=out->origin.y&&fabs(CGRectGetMaxY(r)-out->origin.y)<=5)*out=CGRectUnion(*out,r);
 }
 for(UIView *c in v.subviews){if(*budget<=0)break;rows(c,screen,physical,depth+1,budget,out);}
}
BOOL STHMeasuredKeyboardScene(UIWindowScene *scene,CGRect *mapped,double *inset){
 if(![NSThread isMainThread]||!scene)return NO;
 UIScreen *s=scene.screen;double scale=s.nativeScale;if(scale<=0)return NO;
 CGRect screen=CGRectMake(0,0,s.nativeBounds.size.width/scale,s.nativeBounds.size.height/scale);
 NSMutableArray<UIWindow *> *windows=[NSMutableArray new];
 Class cls=NSClassFromString(@"UIRemoteKeyboardWindow");SEL sel=NSSelectorFromString(@"remoteKeyboardWindowForScreen:create:");
 if([cls respondsToSelector:sel]){id w=((id(*)(id,SEL,UIScreen *,BOOL))objc_msgSend)(cls,sel,s,NO);
  if([w isKindOfClass:UIWindow.class])[windows addObject:w];}
 for(UIWindow *w in UIApplication.sharedApplication.windows)
  if(w.screen==s&&[NSStringFromClass(w.class) containsString:@"Keyboard"]&&![windows containsObject:w])[windows addObject:w];
 CGRect keys=CGRectNull;
 for(UIWindow *w in windows){int budget=800;hosts(w,s,screen,0,&budget,&keys);}
 if(CGRectIsNull(keys))return NO;
 for(int pass=0;pass<3;pass++)for(UIWindow *w in windows){int budget=600;rows(w,s,screen,0,&budget,&keys);}
 // Reject virtual app-height windows which cannot be placed in physical screen
 // coordinates. The host's current-session mapping remains the fallback.
 if(!docked(keys,screen))return NO;
 return STHReadLayoutUsingKeyboard(NSBundle.mainBundle.bundleIdentifier,scene.coordinateSpace.bounds,keys,mapped,inset);
}
