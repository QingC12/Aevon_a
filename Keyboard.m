#if defined(STH_KEYBOARD_TEST)
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#else
#import <UIKit/UIKit.h>
#endif
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import "KeyboardGeometry.h"
#if !defined(STH_KEYBOARD_TEST) || defined(STH_KEYBOARD_INPUT_TEST)
#import "KeyboardFocusBus.h"
extern void *STHCopyInputFocusedModel(void);
extern void *STHCopyInputFocusedModelWithFrame(STHRect *);
extern void STHChooserReleaseSwift(void *);
extern void STHCenterRunAnimation(void (^block)(void),int);
extern BOOL STHSystemActionsEnabled(void);
#endif
#if !defined(STH_KEYBOARD_TEST) || defined(STH_KEYBOARD_INPUT_TEST)
extern void STHStartLayout(void *,CGRect);
extern void STHPrepareLayoutFocus(void *);
extern void STHUpdateLayout(void);
extern void STHStopLayout(void);
#endif

extern CGRect STHNativeRect(void *);
extern NSUInteger STHNativeOrientation(void *);
extern BOOL STHNativeMinimized(void *);
void STHKeyboardModelDidMinimize(void *model);
extern double STHNativeGetScale(void *);
extern CGSize STHNativeGetOffset(void *);
extern void STHNativeSetKeyboardGeometry(void *,const double *);
extern void STHNativeKeyboardShow(void *);
extern void STHNativeKeyboardHide(void);

static __weak id candidate;
static CFTimeInterval candidateAt;
static BOOL candidateConfirmed;
static __weak id owner;
static double saved[3], applied[3];
static BOOL changed;
static BOOL localInput;
static void reconcileKeyboard(void *frameBox,BOOL nativeDelivery);
void STHKeyboardShow(void *frameBox);

static CGRect viewport(void) {
#if defined(STH_KEYBOARD_TEST)
 return CGRectMake(0,0,400,850);
#else
 return UIScreen.mainScreen.bounds;
#endif
}

static void focusModel(void *model,BOOL confirmed) {
 if (![NSThread isMainThread] || !model || localInput) return;
 if(STHNativeMinimized(model)){STHKeyboardModelDidMinimize(model);return;}
 if(!confirmed)return; // A scene hit or drag is not evidence of text-input ownership.
 candidate=(__bridge id)model;candidateConfirmed=YES;
 candidateAt=CACurrentMediaTime();
#if !defined(STH_KEYBOARD_TEST) || defined(STH_KEYBOARD_INPUT_TEST)
 STHPrepareLayoutFocus(model);
#endif
}
void STHKeyboardFocus(void *model){focusModel(model,NO);}
void STHKeyboardInputFocus(void *model){focusModel(model,YES);}

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

// Called by dock reconciliation inside the existing native transition.
void STHKeyboardModelDidMinimize(void *model) {
 if(!NSThread.isMainThread||!model)return;
 id value=(__bridge id)model;
 BOOL owns=owner==value;
 BOOL pending=candidate==value;
 if(!owns&&!pending)return;
#if !defined(STH_KEYBOARD_TEST) || defined(STH_KEYBOARD_INPUT_TEST)
 if(owns||(pending&&!owner))STHStopLayout();
#endif
 if(owns)restoreCard();
 if(pending){candidate=nil;candidateAt=0;candidateConfirmed=NO;}
}

// SpringBoard-local search must never reuse an application's keyboard owner.
void STHKeyboardSetLocalInput(BOOL active){
 if(!NSThread.isMainThread)return;
 localInput=active;
#if !defined(STH_KEYBOARD_TEST) || defined(STH_KEYBOARD_INPUT_TEST)
 STHResetInputFocusReadEpoch();
#endif
 if(active){
#if !defined(STH_KEYBOARD_TEST) || defined(STH_KEYBOARD_INPUT_TEST)
  STHStopLayout();
#endif
  restoreCard();candidate=nil;candidateAt=0;candidateConfirmed=NO;
 }
}
#if !defined(STH_KEYBOARD_TEST) || defined(STH_KEYBOARD_INPUT_TEST)
static void inputOwnerChanged(void){
 if(localInput)return;
 STHRect physical={0,0,0,0};
 void *model=STHSystemActionsEnabled()?STHCopyInputFocusedModelWithFrame(&physical):NULL;
 if(!model){
  if(owner||candidate)STHCenterRunAnimation(^{
   if(localInput)return;
   STHStopLayout();restoreCard();candidate=nil;candidateAt=0;candidateConfirmed=NO;
  },0);
  return;
 }
 STHKeyboardInputFocus(model);
 if(physical.w>=80&&physical.h>=80&&owner!=(__bridge id)model){
#if defined(STH_KEYBOARD_TEST)
  id frame=[NSValue valueWithRect:NSMakeRect(physical.x,physical.y,physical.w,physical.h)];
#else
  id frame=[NSValue valueWithCGRect:CGRectMake(physical.x,physical.y,physical.w,physical.h)];
#endif
  // Apply only geometry from this verified Will. Native notification delivery
  // retains its own one-shot callback and must not be replayed by an IPC wakeup.
  STHCenterRunAnimation(^{if(!localInput)reconcileKeyboard((__bridge void *)frame,NO);},0);
 }
 STHChooserReleaseSwift(model);
}
#if !defined(STH_KEYBOARD_TEST)
__attribute__((constructor)) static void observeKeyboardOwner(void){
 dispatch_async(dispatch_get_main_queue(),^{STHObserveInputFocus(^{inputOwnerChanged();});});
}
#endif
#endif

static void reconcileKeyboard(void *frameBox,BOOL nativeDelivery) {
 if(localInput){if(nativeDelivery)STHNativeKeyboardShow(frameBox);return;}
#if !defined(STH_KEYBOARD_TEST) || defined(STH_KEYBOARD_INPUT_TEST)
 if(!STHSystemActionsEnabled()){
  STHStopLayout();restoreCard();candidate=nil;candidateAt=0;candidateConfirmed=NO;
  if(nativeDelivery)STHNativeKeyboardShow(frameBox);return;
 }
 void *confirmed=STHCopyInputFocusedModel();
 if(confirmed){
  if(candidate!=(__bridge id)confirmed)STHKeyboardInputFocus(confirmed);
  STHChooserReleaseSwift(confirmed);
 }
#endif
 // Strong locals keep the weak model valid for this synchronous transaction.
 id focus=candidateConfirmed?candidate:owner;
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
 if (eligible && (STHNativeMinimized((__bridge void *)focus)||STHNativeOrientation((__bridge void *)focus)!=1)) eligible=NO;
 // Repeated show/frame changes must never overwrite the original snapshot.
 if (currentOwner && currentOwner==focus && eligible) {
  if(nativeDelivery)STHNativeKeyboardShow(frameBox);
#if !defined(STH_KEYBOARD_TEST) || defined(STH_KEYBOARD_INPUT_TEST)
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
#if !defined(STH_KEYBOARD_TEST) || defined(STH_KEYBOARD_INPUT_TEST)
 if(eligible)STHStartLayout((__bridge void *)focus,keyboard);
 else STHStopLayout();
#endif
 if(nativeDelivery)STHNativeKeyboardShow(frameBox); // Original frame publication and avoidance.
 if (currentOwner && (currentOwner!=focus || !eligible)) restoreCard();
 if (enlarge) {
  for (int i=0;i<3;i++) { applied[i]=target[i]; saved[i]=original[i]; }
  owner=focus;changed=YES;
  STHNativeSetKeyboardGeometry((__bridge void *)focus,target);
 }
 if(!eligible){candidate=nil;candidateAt=0;candidateConfirmed=NO;}
#if !defined(STH_KEYBOARD_TEST) || defined(STH_KEYBOARD_INPUT_TEST)
 STHUpdateLayout();
#endif
}

void STHKeyboardShow(void *frameBox){reconcileKeyboard(frameBox,YES);}

void STHKeyboardHide(void) {
#if !defined(STH_KEYBOARD_TEST) || defined(STH_KEYBOARD_INPUT_TEST)
 STHStopLayout();
#endif
 STHNativeKeyboardHide(); // Both restore operations stay in the original spring.
 if ([NSThread isMainThread]) restoreCard();
 candidate=nil;
 candidateAt=0;candidateConfirmed=NO;
}
