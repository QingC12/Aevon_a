#define STH_ROUTING_TEST 1
#define STH_KEYBOARD_TEST 1
#define STH_KEYBOARD_INPUT_TEST 1
#import <objc/runtime.h>
#include <assert.h>
#include <stdio.h>
#ifndef STH_GESTURE_SOURCE
#define STH_GESTURE_SOURCE "Gesture.m"
#endif
#import STH_GESTURE_SOURCE
#if defined(STH_BASELINE28)
void STHGestureInputFocusChanged(void *model){}
#endif
#import "Keyboard.m"

@interface HandoffModel : NSObject
@property unsigned char hitValue;
@property unsigned char latchValue;
@property unsigned char phaseValue;
@property BOOL minimized;
@property double scale;
@property CGSize offset;
@end
@implementation HandoffModel
@end
typedef struct { CGSize translation; } HandoffDrag;
static BOOL keyboardVisible,insideOriginal,insideExpansion;
static HandoffModel *offered;
static STHRect offeredFrame;
static int nativeSetups,nativeUpdates,nativeEnds,nativeTaps,nativeLongs,nativeMoves,nativeDocks;
static int nativeShows,nativeHides,expansions,geometryWrites,contentHits;
NSUInteger STHTestOffset(uintptr_t a){
 const char *key=a==0xf7920?"_hitValue":a==0xf7928?"_latchValue":"_phaseValue";
 return ivar_getOffset(class_getInstanceVariable(HandoffModel.class,key));
}
BOOL STHNativeMinimized(void *p){return ((__bridge HandoffModel *)p).minimized;}
void STHNativeSetMinimized(void *p,BOOL v){((__bridge HandoffModel *)p).minimized=v;}
NSUInteger STHNativeOrientation(void *p){return 1;}
CGRect STHNativeRect(void *p){return STHNativeMinimized(p)?CGRectMake(20,600,40,80):CGRectMake(40,150,320,500);}
int STHNativeClassify(void *p,CGPoint at){
 CGRect r=STHNativeRect(p);
 if(!CGRectContainsPoint(CGRectInset(r,-8,-8),at))return 7;
 if(keyboardVisible&&at.y>=550)return 10;
 return 4;
}
CGSize STHNativeTranslation(void *p){return ((HandoffDrag *)p)->translation;}
void STHNativeSetup(void *p,void *m){nativeSetups++;}
void STHNativeUpdate(void *p,void *m){nativeUpdates++;}
void STHNativeEnd(void *p,void *m){nativeEnds++;}
void STHNativeMove(void *p,CGSize d){nativeMoves++;}
void STHNativeLong(void *p){nativeLongs++;}
void STHNativeReset(void *p){}
void STHNativeTap(void *p,NSUInteger n){nativeTaps++;}
void STHNativeDock(void *p){nativeDocks++;((__bridge HandoffModel *)p).minimized=NO;}
double STHNativeGetScale(void *p){return ((__bridge HandoffModel *)p).scale;}
CGSize STHNativeGetOffset(void *p){return ((__bridge HandoffModel *)p).offset;}
void STHNativeSetKeyboardGeometry(void *p,const double *g){
 assert(insideOriginal);HandoffModel *m=(__bridge HandoffModel *)p;
 m.scale=g[0];m.offset=CGSizeMake(g[1],g[2]);geometryWrites++;
}
void STHNativeKeyboardShow(void *p){assert(insideOriginal&&!insideExpansion);nativeShows++;keyboardVisible=YES;}
void STHNativeKeyboardHide(void){assert(insideOriginal&&!insideExpansion);nativeHides++;keyboardVisible=NO;}
BOOL STHSystemActionsEnabled(void){return YES;}
void STHResetInputFocusReadEpoch(void){}
void *STHCopyInputFocusedModel(void){return offered.minimized?NULL:(__bridge void *)offered;}
void *STHCopyInputFocusedModelWithFrame(STHRect *frame){if(frame)*frame=offeredFrame;return STHCopyInputFocusedModel();}
void STHChooserReleaseSwift(void *p){}
void STHPrepareLayoutFocus(void *p){}
void STHStartLayout(void *p,CGRect r){}
void STHUpdateLayout(void){}
void STHStopLayout(void){}
void STHCenterRunAnimation(void (^block)(void),int style){BOOL old=insideOriginal;insideOriginal=YES;block();insideOriginal=old;}
void STHCardRunExpansion(void (^block)(void)){assert(insideOriginal&&!insideExpansion);insideExpansion=YES;expansions++;block();insideExpansion=NO;}
static void show(NSValue *frame){insideOriginal=YES;STHKeyboardShow((__bridge void *)frame);insideOriginal=NO;}
static void hide(void){insideOriginal=YES;STHKeyboardHide();insideOriginal=NO;}
static HandoffModel *make(void){HandoffModel *m=[HandoffModel new];m.scale=.8;m.offset=CGSizeMake(0,20);return m;}
static int nativeActions(void){return nativeSetups+nativeUpdates+nativeEnds+nativeTaps+nativeLongs+nativeMoves+nativeDocks;}
static BOOL interrupted(void *p){
#if defined(STH_BASELINE28)
 return NO;
#else
 return state(p).inputInterrupted;
#endif
}
static void edge(void *p,HandoffDrag *drag){assert(STHClassify(p,CGPointMake(35,300))==3);STHSetup(drag,p);assert(state(p).dragActive);}
static void content(void *p,HandoffDrag *drag){assert(STHClassify(p,CGPointMake(120,300))==6);contentHits++;STHSetup(drag,p);}
int main(void){@autoreleasepool{
 NSValue *frame=[NSValue valueWithRect:NSMakeRect(0,550,400,300)];
 for(int cycle=0;cycle<200;cycle++){
  HandoffModel *a=make(),*b=make();void *pa=(__bridge void *)a,*pb=(__bridge void *)b;
  HandoffDrag drag={CGSizeZero};offered=nil;offeredFrame=(STHRect){0,0,0,0};
  int shows=nativeShows;show(frame);assert(!owner&&nativeShows==shows+1);
  // No end callback: the keyboard takes the touch while a stationary edge session exists.
  edge(pa,&drag);assert(STHClassify(pa,CGPointMake(120,600))==10);
  assert(!state(pa).dragActive&&interrupted(pa));
  int actions=nativeActions();STHSetup(&drag,pa);STHUpdate(&drag,pa);STHEnd(&drag,pa);STHLong(pa);STHTap(pa,1);
  assert(nativeActions()==actions);content(pa,&drag);
  // A focus-only claim must release the old content gesture without inventing a keyboard frame.
  offered=a;int writes=geometryWrites;inputOwnerChanged();
  assert(candidate==a&&!owner&&geometryWrites==writes&&!state(pa).dragActive);
  assert(interrupted(pa));content(pa,&drag);STHEnd(&drag,pa);
  // The real Will still delivers exactly once, with only card writes in the scoped animation.
  offeredFrame=(STHRect){0,550,400,300};shows=nativeShows;inputOwnerChanged();
  assert(owner==a&&a.scale>.8&&nativeShows==shows);
  writes=geometryWrites;int animations=expansions;show(frame);inputOwnerChanged();
  assert(geometryWrites==writes&&expansions==animations&&nativeShows==shows+1);
  // A new responder interrupts only its own card. Other visible cards remain routable.
  edge(pa,&drag);edge(pb,&drag);offered=b;offeredFrame=(STHRect){0,0,0,0};inputOwnerChanged();
  assert(state(pa).dragActive&&!state(pb).dragActive&&interrupted(pb));
  actions=nativeActions();STHUpdate(&drag,pb);STHEnd(&drag,pb);STHLong(pb);STHTap(pb,1);assert(nativeActions()==actions);
  content(pb,&drag);STHEnd(&drag,pb);STHEnd(&drag,pa);
  // Native keyboard exclusion remains exact; the existing minimized-target exception survives.
  assert(STHClassify(pb,CGPointMake(120,600))==10);
  b.minimized=YES;assert(STHClassify(pb,CGPointMake(40,640))==4);STHSetup(&drag,pb);
  int docks=nativeDocks;STHTap(pb,1);STHEnd(&drag,pb);assert(nativeDocks==docks+1);
  offered=nil;hide();assert(!owner&&!candidate&&fabs(a.scale-.8)<.001);
  content(pa,&drag);STHEnd(&drag,pa);content(pb,&drag);STHEnd(&drag,pb);
 }
 assert(contentHits==1000);
 puts("Floating input handoff: 200 fullscreen-keyboard/focus-only/Will/cancel/late-callback/two-card/dock/restore cycles; keyboard exclusion retained, content routing recovers without native replay");
}return 0;}
