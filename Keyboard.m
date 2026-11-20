#if defined(STH_KEYBOARD_TEST)
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#else
#import <UIKit/UIKit.h>
#endif
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import "KeyboardGeometry.h"
#if !defined(STH_KEYBOARD_TEST)
extern void STHStartLayout(void *,CGRect);
extern void STHPrepareLayoutFocus(void *);
extern void STHUpdateLayout(void);
extern void STHStopLayout(void);
#endif

extern CGRect STHNativeRect(void *);
extern NSUInteger STHNativeOrientation(void *);
extern double STHNativeGetScale(void *);
extern CGSize STHNativeGetOffset(void *);
extern void STHNativeSetKeyboardGeometry(void *,const double *);
extern void STHNativeKeyboardShow(void *);
extern void STHNativeKeyboardHide(void);

static __weak id candidate;
static CFTimeInterval candidateAt;
static __weak id owner;
static double saved[3], applied[3];
static BOOL changed;

static CGRect viewport(void) {
#if defined(STH_KEYBOARD_TEST)
 return CGRectMake(0,0,400,850);
#else
 return UIScreen.mainScreen.bounds;
#endif
}

void STHKeyboardFocus(void *model) {
 if (![NSThread isMainThread] || !model) return;
 candidate=(__bridge id)model;
 candidateAt=CACurrentMediaTime();
#if !defined(STH_KEYBOARD_TEST)
 STHPrepareLayoutFocus(model);
#endif
}

static void restoreCard(void) {
 id strongOwner=owner;
 owner=nil;
 if (!strongOwner || !changed) { changed=NO; return; }
 changed=NO;
 void *model=(__bridge void *)strongOwner;
 double currentScale=STHNativeGetScale(model);
 CGSize currentOffset=STHNativeGetOffset(model);
 // Respect changes the user made while the keyboard was open.
 double geometry[3]={currentScale,currentOffset.width,currentOffset.height};
 if (fabs(currentScale-applied[0])<.001) geometry[0]=saved[0];
 if (hypot(currentOffset.width-applied[1],currentOffset.height-applied[2])<.5) {
  geometry[1]=saved[1]; geometry[2]=saved[2];
 }
 STHNativeSetKeyboardGeometry(model,geometry);
}

void STHKeyboardShow(void *frameBox) {
 // Strong locals keep the weak model valid for this synchronous transaction.
 id focus=candidate;
 id currentOwner=owner;
 CGRect screen=viewport();
 id input=(__bridge id)frameBox;
 CGRect keyboard=CGRectNull;
 BOOL ownerMismatch=currentOwner&&currentOwner!=focus;
 if(ownerMismatch){restoreCard();currentOwner=nil;}
 if ([input isKindOfClass:NSValue.class]) {
#if defined(STH_KEYBOARD_TEST)
  if ([input respondsToSelector:@selector(rectValue)]) keyboard=[input rectValue];
#else
  if ([input respondsToSelector:@selector(CGRectValue)]) keyboard=[input CGRectValue];
#endif
 }
 BOOL eligible=[NSThread isMainThread] && focus &&
   ((currentOwner&&currentOwner==focus)||CACurrentMediaTime()-candidateAt<2.0)
   && !CGRectIsNull(keyboard) && !CGRectIsEmpty(keyboard)
   && CGRectGetHeight(keyboard)>80 && CGRectGetWidth(keyboard)>.72*CGRectGetWidth(screen)
   && CGRectGetMinY(keyboard)>CGRectGetMinY(screen)
   && CGRectGetMinY(keyboard)<CGRectGetMaxY(screen)-40
   && CGRectGetMaxY(keyboard)>=CGRectGetMaxY(screen)-20;
 if (eligible && STHNativeOrientation((__bridge void *)focus)!=1) eligible=NO;
 // Repeated show/frame changes must never overwrite the original snapshot.
 if (currentOwner && currentOwner==focus && eligible) {
  STHNativeKeyboardShow(frameBox);
#if !defined(STH_KEYBOARD_TEST)
  STHStartLayout((__bridge void *)focus,keyboard);
#endif
  return;
 }
 double target[3]={0,0,0}, original[3]={0,0,0};
 BOOL enlarge=NO;
 if (eligible) {
  void *model=(__bridge void *)focus;
  CGRect card=STHNativeRect(model);
  double scale=STHNativeGetScale(model);
  CGSize position=STHNativeGetOffset(model);
  if (CGRectGetWidth(card)>80 && CGRectGetHeight(card)>80 && isfinite(scale)) {
   double factor=STHKeyboardScaleFactor(scale,CGRectGetWidth(card),CGRectGetWidth(screen));
   original[0]=scale;original[1]=position.width;original[2]=position.height;
   target[0]=scale*factor;
   // Full-width card must be centered, even if the old floating card was offset.
   target[1]=position.width+CGRectGetMidX(screen)-CGRectGetMidX(card);
   target[2]=position.height+STHKeyboardVisibleDelta(CGRectGetMinY(card),CGRectGetHeight(card),factor,
       CGRectGetMinY(screen),CGRectGetMinY(keyboard));
   enlarge=fabs(factor-1.0)>.00001 || fabs(target[1]-position.width)>.01 || fabs(target[2]-position.height)>.01;
  }
 }
#if !defined(STH_KEYBOARD_TEST)
 if(eligible)STHStartLayout((__bridge void *)focus,keyboard);
 else STHStopLayout();
#endif
 STHNativeKeyboardShow(frameBox); // Original frame publication and avoidance.
 if (currentOwner && (currentOwner!=focus || !eligible)) restoreCard();
 if (enlarge) {
  for (int i=0;i<3;i++) { applied[i]=target[i]; saved[i]=original[i]; }
  owner=focus;changed=YES;
  STHNativeSetKeyboardGeometry((__bridge void *)focus,target);
 }
 if(!eligible){candidate=nil;candidateAt=0;}
#if !defined(STH_KEYBOARD_TEST)
 STHUpdateLayout();
#endif
}

void STHKeyboardHide(void) {
#if !defined(STH_KEYBOARD_TEST)
 STHStopLayout();
#endif
 STHNativeKeyboardHide(); // Both restore operations stay in the original spring.
 if ([NSThread isMainThread]) restoreCard();
 candidate=nil;
 candidateAt=0;
}
