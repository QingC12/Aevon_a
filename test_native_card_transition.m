#define STH_KEYBOARD_TEST 1
#define STH_KEYBOARD_INPUT_TEST 1
#import <assert.h>
#import <stdio.h>
#import <string.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
static NSMutableArray *pendingInputReads;
static void transitionAsync(dispatch_queue_t queue,dispatch_block_t block){
 assert(queue==dispatch_get_main_queue());
 if(!pendingInputReads)pendingInputReads=[NSMutableArray new];
 [pendingInputReads addObject:[block copy]];
}
#define dispatch_async transitionAsync
#ifndef STH_KEYBOARD_SOURCE
#define STH_KEYBOARD_SOURCE "Keyboard.m"
#endif
#import STH_KEYBOARD_SOURCE
#undef dispatch_async
@interface TransitionModel:NSObject
@property double scale;
@property CGSize offset;
@property BOOL minimized;
@end
@implementation TransitionModel @end
static TransitionModel *offered;
static STHRect offeredFrame;
static BOOL enabled=YES,allowOldSpring;
static int transaction,geometryWrites,nativeShows,nativeHides,layoutStops,originalAnimations;
static int nestedAnimations,inputReads;
BOOL STHSystemActionsEnabled(void){return enabled;}
void STHResetInputFocusReadEpoch(void){}
void STHGestureInputFocusChanged(void *p){}
void *STHCopyInputFocusedModel(void){return offered.minimized?NULL:(__bridge void *)offered;}
void *STHCopyInputFocusedModelWithFrame(STHRect *p){inputReads++;if(p)*p=offeredFrame;return STHCopyInputFocusedModel();}
void STHChooserReleaseSwift(void *p){}
void STHPrepareLayoutFocus(void *p){}
void STHStartLayout(void *p,CGRect r){}
void STHUpdateLayout(void){}
void STHStopLayout(void){layoutStops++;}
NSUInteger STHNativeOrientation(void *p){return 1;}
BOOL STHNativeMinimized(void *p){return ((__bridge TransitionModel *)p).minimized;}
double STHNativeGetScale(void *p){return ((__bridge TransitionModel *)p).scale;}
CGSize STHNativeGetOffset(void *p){return ((__bridge TransitionModel *)p).offset;}
CGRect STHNativeRect(void *p){
 TransitionModel *m=(__bridge TransitionModel *)p;
 double w=400*m.scale,h=625*m.scale;
 return CGRectMake(200+m.offset.width-w/2,380+m.offset.height-h/2,w,h);
}
void STHNativeSetKeyboardGeometry(void *p,const double *g){
 assert(transaction!=0);
 assert(allowOldSpring||transaction!=3); // No card-only nested spring.
 TransitionModel *m=(__bridge TransitionModel *)p;m.scale=g[0];m.offset=CGSizeMake(g[1],g[2]);geometryWrites++;
}
void STHNativeKeyboardShow(void *p){assert(transaction==1);nativeShows++;}
void STHNativeKeyboardHide(void){assert(transaction==1);nativeHides++;}
void STHCenterRunAnimation(void (^block)(void),int style){
 assert(style==0);int old=transaction;transaction=2;originalAnimations++;block();transaction=old;
}
// A linked old-source negative control exposes the mismatched nested transaction.
void STHCardRunExpansion(void (^block)(void)){
 int old=transaction;transaction=3;nestedAnimations++;block();transaction=old;
}
static void show(NSValue *frame){transaction=1;STHKeyboardShow((__bridge void *)frame);transaction=0;}
static void hide(void){transaction=1;STHKeyboardHide();transaction=0;}
static void recheck(NSUInteger generation){
 NSArray *turn=[pendingInputReads copy];[pendingInputReads removeAllObjects];
 for(dispatch_block_t block in turn)block();
 assert(pendingInputReads.count==0); // Exactly one confirmation, never a retry loop.
}
static NSUInteger readGeneration(void){
#if defined(STH_OLD_TRANSITION)
 return 0;
#else
 return inputReadGeneration;
#endif
}
static TransitionModel *make(void){TransitionModel *m=[TransitionModel new];m.scale=.8;m.offset=CGSizeMake(0,20);return m;}
static void assertExpanded(TransitionModel *m){assert(owner==m&&fabs(m.scale-1)<.001&&fabs(STHNativeRect((__bridge void *)m).size.width-400)<.001);}
int main(int argc,char **argv){@autoreleasepool{
 allowOldSpring=argc>1&&!strcmp(argv[1],"--transient");
 NSValue *frame=[NSValue valueWithRect:NSMakeRect(0,550,400,300)];
 for(int i=0;i<200;i++){
  TransitionModel *a=make();offered=a;offeredFrame=(STHRect){0,550,400,300};
  // Claim-first: the native caller's existing spring owns the geometry write.
  int before=nativeShows;show(frame);assert(nativeShows==before+1);assertExpanded(a);
  double snapshot[3]={saved[0],saved[1],saved[2]};
  assert(fabs(snapshot[0]-.8)<.001&&fabs(snapshot[2]-20)<.001);
  int writes=geometryWrites,animations=originalAnimations;
  inputOwnerChanged();show(frame);assert(geometryWrites==writes&&originalAnimations==animations);
  // An unavailable snapshot must not produce shrink -> enlarge between two reads.
  int reads=inputReads,stops=layoutStops;
  offered=nil;inputOwnerChanged();NSUInteger first=readGeneration();
  assert(owner==a&&geometryWrites==writes); // Exact 28/29 code fails here.
  assert(inputReads==reads+1&&pendingInputReads.count==1&&layoutStops==stops);
  offered=a;recheck(first);assertExpanded(a);assert(geometryWrites==writes);
  assert(inputReads==reads+2&&layoutStops==stops);
  assert(!memcmp(saved,snapshot,sizeof(snapshot)));
  // An explicit newer event supersedes a queued empty-read confirmation.
  offered=nil;inputOwnerChanged();first=readGeneration();offered=a;inputOwnerChanged();
  recheck(first);assertExpanded(a);assert(geometryWrites==writes);
  // A positive native callback also supersedes a pending empty owner read.
  offered=nil;inputOwnerChanged();first=readGeneration();offered=a;show(frame);
  offered=nil;recheck(first);assertExpanded(a);assert(geometryWrites==writes);offered=a;
  // A persistent loss gets exactly one bounded restore; a duplicate completion is inert.
  offered=nil;inputOwnerChanged();first=readGeneration();recheck(first);
  assert(!owner&&!candidate&&fabs(a.scale-.8)<.001&&geometryWrites==writes+1);
  recheck(first);assert(geometryWrites==writes+1);
  // Frame-first: late owner uses the existing original-parameter fallback, never native replay.
  hide();offered=nil;before=nativeShows;show(frame);assert(nativeShows==before+1&&!owner);
  offered=a;inputOwnerChanged();assertExpanded(a);assert(nativeShows==before+1);
  // Native hide cancels the stale recheck and must not reopen/re-expand the card.
  offered=nil;inputOwnerChanged();first=readGeneration();hide();writes=geometryWrites;
  offered=a;recheck(first);assert(!owner&&geometryWrites==writes&&fabs(a.scale-.8)<.001);
  // Local input and minimized cleanup invalidate their pending handoff independently.
  inputOwnerChanged();assertExpanded(a);offered=nil;inputOwnerChanged();first=readGeneration();
  transaction=1;STHKeyboardSetLocalInput(YES);transaction=0;writes=geometryWrites;
  offered=a;recheck(first);assert(!owner&&geometryWrites==writes);STHKeyboardSetLocalInput(NO);
  inputOwnerChanged();assertExpanded(a);offered=nil;inputOwnerChanged();first=readGeneration();
  a.minimized=YES;transaction=1;STHKeyboardModelDidMinimize((__bridge void *)a);transaction=0;writes=geometryWrites;
  recheck(first);assert(!owner&&geometryWrites==writes);a.minimized=NO;offered=nil;hide();
 }
 assert(nestedAnimations==0);
 puts("Native card transition: 200 dynamic-geometry cycles; no nested spring, no transient empty-read shrink/enlarge, single bounded loss confirmation, native hide/local input/dock cancel stale work; original target and snapshot retained");
}return 0;}
