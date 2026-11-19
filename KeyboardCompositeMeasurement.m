// Used only by the four remaining app profiles. Known-good2.0.11 measurement
// stays unchanged for QQ/Minis and all other bundles. Geometry, never text.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "LayoutBus.h"
#import "KeyboardAccessoryMath.h"
static BOOL docked(CGRect r,CGRect screen){return isfinite(r.origin.x)&&isfinite(r.origin.y)&&
 isfinite(r.size.width)&&isfinite(r.size.height)&&r.size.width>=screen.size.width*.7&&r.size.height>=60&&
 r.size.height<screen.size.height*.7&&fabs(CGRectGetMaxY(r)-CGRectGetMaxY(screen))<=6;}
static BOOL excluded(UIView *v,NSArray<UIView *> *appRows){
 for(UIView *row in appRows)if(v==row||[v isDescendantOfView:row])return YES;return NO;
}
static BOOL wrapsAppRow(UIView *v,NSArray<UIView *> *appRows){
 for(UIView *row in appRows)if(v==row||[row isDescendantOfView:v]||[v isDescendantOfView:row])return YES;return NO;
}
static void hosts(UIView *v,UIScreen *screen,CGRect physical,NSArray *appRows,int depth,int *budget,CGRect *exact,CGRect *fallback){
 if(!v||v.hidden||v.alpha<.01||depth>18||--*budget<0||excluded(v,appRows))return;
 NSString *n=NSStringFromClass(v.class);
 BOOL specific=[n containsString:@"InputSetHost"]||[n containsString:@"RemoteKeyboardPlaceholder"];
 if(specific||[n containsString:@"InputSetContainer"]){
  CGRect r=[v convertRect:v.bounds toCoordinateSpace:screen.fixedCoordinateSpace];
  if(docked(r,physical)){
   CGRect *out=specific?exact:fallback;*out=CGRectIsNull(*out)?r:CGRectUnion(*out,r);
  }
 }
 for(UIView *c in v.subviews){if(*budget<=0)break;hosts(c,screen,physical,appRows,depth+1,budget,exact,fallback);}
}
static void coreKeys(UIView *v,UIScreen *screen,CGRect physical,NSArray *appRows,int depth,int *budget,CGRect *out){
 if(!v||v.hidden||v.alpha<.01||depth>20||--*budget<0||excluded(v,appRows))return;
 NSString *n=NSStringFromClass(v.class);
 NSString *bundle=[NSBundle bundleForClass:v.class].bundleIdentifier;
 BOOL layout=[n containsString:@"UIKeyboardLayoutStar"]||[n containsString:@"UIKBKeyplaneView"]||
             [n containsString:@"UIKeyboardLayoutView"]||[n containsString:@"UIKeyboardImpl"];
 if(layout&&[bundle hasPrefix:@"com.apple."]&&!wrapsAppRow(v,appRows)){
  CGRect r=[v convertRect:v.bounds toCoordinateSpace:screen.fixedCoordinateSpace];
  if(docked(r,physical))*out=CGRectIsNull(*out)?r:CGRectUnion(*out,r);
 }
 for(UIView *c in v.subviews){if(*budget<=0)break;coreKeys(c,screen,physical,appRows,depth+1,budget,out);}
}
static void rows(UIView *v,UIScreen *screen,CGRect physical,NSArray *appRows,int depth,int *budget,CGRect *out){
 if(!v||v.hidden||v.alpha<.01||depth>18||--*budget<0||excluded(v,appRows))return;
 NSString *n=NSStringFromClass(v.class).lowercaseString;
 NSString *owner=[NSBundle bundleForClass:v.class].bundleIdentifier;
 BOOL systemOwned=[owner hasPrefix:@"com.apple."];
 BOOL keyboardRow=[n containsString:@"candidate"]||[n containsString:@"prediction"]||
   [n containsString:@"quicktype"]||[n containsString:@"inputassistant"]||[n containsString:@"keyboardtoolbar"];
 if(systemOwned&&!wrapsAppRow(v,appRows)&&keyboardRow){
  CGRect r=[v convertRect:v.bounds toCoordinateSpace:screen.fixedCoordinateSpace];
  if(r.size.width>=physical.size.width*.7&&r.size.height>=8&&r.size.height<=160&&r.origin.y>=0&&
    r.origin.y<=out->origin.y&&fabs(CGRectGetMaxY(r)-out->origin.y)<=5)*out=CGRectUnion(*out,r);
 }
 for(UIView *c in v.subviews){if(*budget<=0)break;rows(c,screen,physical,appRows,depth+1,budget,out);}
}
BOOL STHMeasuredKeyboardComposite(UIWindowScene *scene,UIView *field,CGRect *mapped,double *inset){
 if(![NSThread isMainThread]||!scene||!field)return NO;
 UIScreen *s=scene.screen;double scale=s.nativeScale;if(scale<=0)return NO;
 CGRect physical=CGRectMake(0,0,s.nativeBounds.size.width/scale,s.nativeBounds.size.height/scale);
 NSMutableArray<UIView *> *appRows=[NSMutableArray new];
 // inputAccessoryView is app UI even when UIKit reparents it into a system
 // host. BundleForClass on that wrapper is not evidence of system ownership.
 UIResponder *r=field;
 for(int depth=0;r&&r!=field.window&&depth<20;depth++,r=r.nextResponder){
  UIView *a=r.inputAccessoryView;
  if(a.window&&!a.hidden&&a.alpha>.01&&![appRows containsObject:a])[appRows addObject:a];
 }
 NSMutableArray<UIWindow *> *windows=[NSMutableArray new];
 Class cls=NSClassFromString(@"UIRemoteKeyboardWindow");SEL sel=NSSelectorFromString(@"remoteKeyboardWindowForScreen:create:");
 if([cls respondsToSelector:sel]){id w=((id(*)(id,SEL,UIScreen *,BOOL))objc_msgSend)(cls,sel,s,NO);
  if([w isKindOfClass:UIWindow.class])[windows addObject:w];}
 for(UIWindow *w in UIApplication.sharedApplication.windows)
  if(w.screen==s&&[NSStringFromClass(w.class) containsString:@"Keyboard"]&&![windows containsObject:w])[windows addObject:w];
 CGRect exact=CGRectNull,fallback=CGRectNull,core=CGRectNull;
 for(UIWindow *w in windows){int budget=1100;coreKeys(w,s,physical,appRows,0,&budget,&core);}
 for(UIWindow *w in windows){int budget=900;hosts(w,s,physical,appRows,0,&budget,&exact,&fallback);}
 // A narrow keyplane/keyboard layout is stronger than a broad app-accessory
 // host. If neither is measurable, keep the existing host layout fallback.
 CGRect keys=CGRectIsNull(core)?(CGRectIsNull(exact)?fallback:exact):core;
 if(CGRectIsNull(keys))return NO;
 for(int pass=0;pass<3;pass++)for(UIWindow *w in windows){int budget=650;rows(w,s,physical,appRows,0,&budget,&keys);}
 // If an identified app accessory occupies the top of a broad host container,
 // remove precisely that measured band. Never subtract a guessed27/57/61pt.
 for(UIView *a in appRows){
  CGRect r=[a convertRect:a.bounds toCoordinateSpace:s.fixedCoordinateSpace];
  STHRect trimmed;
  if(STHExcludeAppAccessory((STHRect){keys.origin.x,keys.origin.y,keys.size.width,keys.size.height},
      (STHRect){r.origin.x,r.origin.y,r.size.width,r.size.height},physical.size.width,physical.size.height,&trimmed))
   keys=CGRectMake(trimmed.x,trimmed.y,trimmed.w,trimmed.h);
 }
 if(!docked(keys,physical))return NO;
 return STHReadLayoutUsingKeyboard(NSBundle.mainBundle.bundleIdentifier,scene.coordinateSpace.bounds,keys,mapped,inset);
}
