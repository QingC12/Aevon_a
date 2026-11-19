#if defined(STH_ROUTING_TEST)
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#else
#import <UIKit/UIKit.h>
#endif
#import <QuartzCore/QuartzCore.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <math.h>

uintptr_t sth_core_base=0;
extern CGRect STHNativeRect(void *);
extern void STHNativeReset(void *);
extern void STHNativeDock(void *);
extern NSUInteger STHNativeOrientation(void *);
extern void STHNativeSetup(void *,void *);
extern void STHNativeUpdate(void *,void *);
extern void STHNativeEnd(void *,void *);
extern void STHNativeLong(void *);
extern void STHNativeTap(void *,NSUInteger);
extern int STHNativeClassify(void *,CGPoint);
extern CGSize STHNativeTranslation(void *);
extern void STHNativeMove(void *,CGSize);

typedef NS_ENUM(int, Zone) { ZOriginal, ZSide, ZCorner, ZRotate, ZReset, ZMove, ZReturnPortrait };
@interface STHGestureState : NSObject
@property Zone zone;
@property CGPoint start;
@property double began;
@property CGSize moveOrigin;
@property BOOL moveOriginSet;
@property BOOL moving;
@property BOOL acted;
@property BOOL active;
@property BOOL dragActive;
@property unsigned char lockedHit;
@property BOOL holdArmed;
@property NSUInteger generation;
@property double lastTapAt;
@property CGPoint lastTapPoint;
@end
@implementation STHGestureState
@end
static NSMapTable *states;
static void ensureBase(void) {
 if(sth_core_base)return;
 for(uint32_t i=0;i<_dyld_image_count();i++) {
  const char *n=_dyld_get_image_name(i);
  if(n&&[[[NSString stringWithUTF8String:n] lastPathComponent] isEqualToString:@"Stheno.dylib"]){sth_core_base=(uintptr_t)_dyld_get_image_header(i);break;}
 }
}
static NSUInteger offset(uintptr_t address) {
#if defined(STH_ROUTING_TEST)
 extern NSUInteger STHTestOffset(uintptr_t);
 return STHTestOffset(address);
#else
 ensureBase();
 return *(NSUInteger *)(sth_core_base+address);
#endif
}
static unsigned char *hit(void *m) { return (unsigned char *)m+offset(0xf7920); }
static unsigned char *latch(void *m) { return (unsigned char *)m+offset(0xf7928); }
static unsigned char *phase(void *m) { return (unsigned char *)m+offset(0xf7930); }
static STHGestureState *state(void *m) { return [states objectForKey:(__bridge id)m]; }
static BOOL portrait(void) {
#if !defined(STH_ROUTING_TEST)
 for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
  if ([s isKindOfClass:UIWindowScene.class]) return UIInterfaceOrientationIsPortrait(((UIWindowScene *)s).interfaceOrientation);
#endif
 return YES;
}
static STHGestureState *registerState(void *m) {
 STHGestureState *s=state(m);
 if (!s) { s=[STHGestureState new]; [states setObject:s forKey:(__bridge id)m]; }
 return s;
}
// Preserve membership in the ORIGINAL hit region. Subdivide it along its length only.
int STHClassify(void *m,CGPoint p) {
 ensureBase();
 STHGestureState *s=state(m);
 // Native scene hit-testing may query classification again during a drag.
 if (s.dragActive && s.zone==ZMove) return s.lockedHit;
 int original=STHNativeClassify(m,p);
#if !defined(STH_ROUTING_TEST)
 if (original==6) {
  extern void STHKeyboardFocus(void *);
  STHKeyboardFocus(m);
 }
#endif
 s=registerState(m);
 s.lockedHit=(unsigned char)original;
 s.zone=ZOriginal;
 s.start=p;
 s.began=CACurrentMediaTime();
 s.moving=NO;
 s.acted=NO;
 s.active=YES;
 s.holdArmed=NO;
 s.moveOriginSet=NO;
 s.moveOrigin=CGSizeZero;
 s.generation++;
 if (original<1 || original>4) return original;
 CGRect r=STHNativeRect(m);
 if (CGRectIsEmpty(r)||!isfinite(r.origin.x)||!isfinite(r.origin.y)||!isfinite(r.size.width)||!isfinite(r.size.height)) return original;
 CGFloat x=(p.x-CGRectGetMinX(r))/r.size.width;
 CGFloat radius=MIN(r.size.width,r.size.height)*0.15;
 BOOL bottom=p.y>=CGRectGetMaxY(r)-radius;
 NSUInteger orientation=STHNativeOrientation(m);
 if (orientation==3 || orientation==4) {
  // The original edge-middle strip remains reachable after rotation.
  if (original==4 || (bottom && x>=0.15 && x<0.35)) s.zone=ZReturnPortrait;
  return original;
 }
 if (!portrait()) return original;
 if (bottom) {
  if (x<0.15||x>0.85) s.zone=ZCorner;
  else if (x<0.35) s.zone=ZRotate;
  else if (x>0.65) s.zone=ZReset;
  else s.zone=ZMove;
 } else if (p.x<CGRectGetMinX(r)||p.x>CGRectGetMaxX(r)) s.zone=ZSide;
 if (s.zone==ZOriginal) return original;
 // Keep the yellow strip in the ORIGINAL edge-middle class for drag end.
 // Continuous movement is dispatched separately without changing close recognition.
 s.lockedHit=s.zone==ZMove?4:(s.zone==ZCorner?2:3);
 return s.lockedHit;
}
void STHSetup(void *drag,void *m) {
 STHGestureState *s=state(m);
 s.dragActive=YES;
 if (!s||s.zone==ZOriginal||s.zone==ZReturnPortrait) {STHNativeSetup(drag,m);return;}
 *hit(m)=s.zone==ZMove?4:(s.zone==ZCorner?2:3);*latch(m)=0;*phase(m)=2;
 STHNativeSetup(drag,m);
}
void STHUpdate(void *drag,void *m) {
 ensureBase();
 STHGestureState *s=state(m);
 CGSize translation=STHNativeTranslation(drag);
 BOOL displaced=hypot(translation.width,translation.height)>3.0;
 if (!s||s.zone==ZOriginal||s.zone==ZReturnPortrait){if(displaced)s.moving=YES;if(!s.acted)STHNativeUpdate(drag,m);return;}
 if (s.zone==ZRotate||s.zone==ZReset||s.acted) return;
 if (s.zone==ZCorner) {
  *hit(m)=2;
  *latch(m)=0;
  STHNativeUpdate(drag,m);
  return;
 }
 if (s.zone==ZMove) {
  // No hold gate: move immediately, then leave all release recognition to Stheno.
  *hit(m)=4;
  *latch(m)=0;
  s.moving=s.moving||displaced;
  STHNativeMove(m,translation);
  return;
 }
 if (s.zone==ZSide && !s.holdArmed) return;
 if (!displaced && !s.moving) return;
 s.moving=YES;
 *hit(m)=3;
 *latch(m)=0;
 // The native drag path measures translation from its first accepted sample.
 if (!s.moveOriginSet) {
  s.moveOrigin=translation;
  s.moveOriginSet=YES;
 }
 CGSize delta=CGSizeMake(translation.width-s.moveOrigin.width,
                        translation.height-s.moveOrigin.height);
 STHNativeMove(m,delta);
}
void STHEnd(void *drag,void *m) {
 ensureBase();
 STHGestureState *s=state(m);s.active=NO;s.dragActive=NO;
 if (!s||s.zone==ZOriginal||s.zone==ZReturnPortrait){if(!*latch(m)&&!s.acted)STHNativeEnd(drag,m);return;}
 CGSize t=STHNativeTranslation(drag);
 BOOL click=s.zone==ZSide&&!s.holdArmed&&!s.moving&&!s.acted&&hypot(t.width,t.height)<=10.0;
 if (s.zone==ZMove) {
  // Native end includes its original flick threshold, cleanup and close animation.
  // Never pre-clean the gesture as a movement-class gesture before this call.
  *hit(m)=4;
  *latch(m)=0;
  STHNativeEnd(drag,m);
  return;
 }
 *hit(m)=s.zone==ZCorner?2:3;
 *latch(m)=0;
 STHNativeEnd(drag,m);
 if (click) {
  s.acted=YES;
  STHNativeDock(m);
 }
}
void STHLong(void *m) {
 STHGestureState *s=state(m);
 if (!s||s.zone==ZOriginal) {
  // The underlying recognizer is now .25s. Preserve the original .5s elsewhere.
  *latch(m)=0;
  void (*retain)(void *)=dlsym(RTLD_DEFAULT,"swift_retain");
  void (*release)(void *)=dlsym(RTLD_DEFAULT,"swift_release");
  NSUInteger generation=s.generation;
  if(retain&&release){retain(m);dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.25*NSEC_PER_SEC)),dispatch_get_main_queue(),^{STHGestureState *t=state(m);if(t&&t.generation==generation&&t.active&&!t.moving){*latch(m)=1;STHNativeLong(m);}release(m);});}
  return;
 }
 if (s.acted)return;
 if(s.zone==ZSide){s.holdArmed=YES;*latch(m)=0;return;}
 if (s.zone==ZMove) {
  // Yellow does not arm a long-press mode and must not suppress drag-end.
  *hit(m)=4;
  *latch(m)=0;
  return;
 }
 if (s.zone==ZCorner) { *latch(m)=0; return; }
 if (s.zone==ZRotate || s.zone==ZReturnPortrait) {
  s.acted=YES;
  unsigned char previous=*hit(m);
  *hit(m)=4;
  STHNativeLong(m);
  *hit(m)=previous;
  return;
 }
 if(s.zone==ZReset){
  s.acted=YES;
  // Restore the actual tuple from ReflectManager's initializer and clear aspect trim.
  STHNativeReset(m);
 }
}
void STHTap(void *m,NSUInteger count) {
 STHGestureState *s=state(m);
 if(!s||s.zone==ZOriginal||s.zone==ZReturnPortrait){
  if(s.acted)return;
  NSUInteger mask=[[[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.nx.stheno"] objectForKey:@"SettingMask"] unsignedIntegerValue];
  NSUInteger wanted=(mask&0x10000)?1:2;
  double now=CACurrentMediaTime();
  BOOL second=s.lastTapAt>0&&now-s.lastTapAt<0.35&&hypot(s.start.x-s.lastTapPoint.x,s.start.y-s.lastTapPoint.y)<30;
  if(wanted==1||second){s.lastTapAt=0;STHNativeTap(m,wanted);}else{s.lastTapAt=now;s.lastTapPoint=s.start;}
  return;
 }
 if(s.zone==ZSide&&!s.holdArmed&&!s.moving&&!s.acted){s.acted=YES;STHNativeDock(m);}
}
__attribute__((constructor)) static void init(void) {
 states=[NSMapTable weakToStrongObjectsMapTable];
 for(uint32_t i=0;i<_dyld_image_count();i++) {
  const char *n=_dyld_get_image_name(i);
  if(n&&[[[NSString stringWithUTF8String:n] lastPathComponent] isEqualToString:@"Stheno.dylib"]){sth_core_base=(uintptr_t)_dyld_get_image_header(i);break;}
 }
 // Stheno may load later: refresh before export invocation via patched lookup.
}
