#define STH_ROUTING_TEST 1
#import <objc/runtime.h>
#include <stdio.h>
#import "Gesture.m"
#include <assert.h>
#include <stddef.h>

typedef struct { CGSize translation; BOOL flick; } Drag;
@interface TestModel : NSObject
@property unsigned char hitValue;
@property unsigned char latchValue;
@property unsigned char phaseValue;
@end
@implementation TestModel
@end
static int setups, ends, moves, docked, longs, updates;
static unsigned char endHit;
static BOOL endHeld, nativeWouldClose;
static CGSize movedBy;

NSUInteger STHTestOffset(uintptr_t address) {
 const char *name=address==0xf7920?"_hitValue":address==0xf7928?"_latchValue":"_phaseValue";
 return ivar_getOffset(class_getInstanceVariable(TestModel.class,name));
}
static int nativeHit=4;static BOOL testMinimized;
BOOL STHNativeMinimized(void *m){return testMinimized;}
void STHNativeSetMinimized(void *m,BOOL value){testMinimized=value;}
CGRect STHNativeRect(void *m) { return CGRectMake(20,20,200,400); }
int STHNativeClassify(void *m,CGPoint p) { return nativeHit; }
NSUInteger STHNativeOrientation(void *m) { return 1; }
CGSize STHNativeTranslation(void *drag) { return ((Drag *)drag)->translation; }
void STHNativeMove(void *m,CGSize t) { moves++;movedBy=t; }
void STHNativeSetup(void *d,void *m) { setups++; }
void STHNativeUpdate(void *d,void *m) { updates++; }
void STHNativeEnd(void *d,void *m) {
 ends++;endHit=*hit(m);endHeld=*latch(m);
 nativeWouldClose=endHit==4&&!endHeld&&((Drag *)d)->flick;
}
void STHNativeDock(void *m) { docked++;testMinimized=NO; }
void STHNativeLong(void *m) { longs++; }
void STHNativeReset(void *m) {}
void STHNativeTap(void *m,NSUInteger c) {}
CGRect STHTestScreenBounds(void) { return CGRectMake(0,0,600,600); }

static void beginYellow(TestModel *model,Drag *drag) {
 void *m=(__bridge void *)model;
 int category=STHClassify(m,CGPointMake(120,422));
 assert(category==4);
 model.hitValue=category;
 STHSetup(drag,m);
 assert(model.hitValue==4);
}
int main(void) {
 @autoreleasepool {
  TestModel *model=[TestModel new];void *m=(__bridge void *)model;
  nativeHit=10;
  assert(STHClassify(m,CGPointMake(120,200))==10);
  nativeHit=4;
  Drag drag={CGSizeZero,YES};
  beginYellow(model,&drag);
  drag.translation=CGSizeMake(8,-50);STHUpdate(&drag,m);
  assert(moves==1&&fabs(movedBy.height+50)<.001);
  assert(model.hitValue==4&&model.latchValue==0);
  assert(STHClassify(m,CGPointMake(221,100))==4); // Native scene re-hit during movement.
  assert(state(m).zone==ZMove);
  STHEnd(&drag,m);
  assert(ends==1&&endHit==4&&!endHeld&&nativeWouldClose);

  drag=(Drag){CGSizeZero,YES};beginYellow(model,&drag);
  model.latchValue=1;STHLong(m); // Original recognizer sets the latch before callback.
  assert(model.latchValue==0&&model.hitValue==4&&longs==0);
  drag.translation=CGSizeMake(0,-80);STHUpdate(&drag,m);STHEnd(&drag,m);
  assert(ends==2&&nativeWouldClose);

  drag=(Drag){CGSizeZero,NO};beginYellow(model,&drag);
  drag.translation=CGSizeMake(35,10);STHUpdate(&drag,m);STHEnd(&drag,m);
  assert(ends==3&&!nativeWouldClose);
  assert(fabs(movedBy.width-35)<.001&&fabs(movedBy.height-10)<.001);
  assert(docked==0&&updates==0&&setups==3);
  assert(STHClassify(m,CGPointMake(120,120))==6);
  STHSetup(&drag,m);
  nativeHit=10;
  assert(STHClassify(m,CGPointMake(120,120))==10);
  assert(!state(m).dragActive&&state(m).inputInterrupted);
  nativeHit=4;
  assert(STHClassify(m,CGPointMake(120,120))==6);
  STHSetup(&drag,m);
  assert(STHClassify(m,CGPointMake(222,420))==6);
  STHUpdate(&drag,m);STHLong(m);STHTap(m,1);STHEnd(&drag,m);
  assert(docked==0&&updates==0&&setups==3&&ends==3&&longs==0);
  drag=(Drag){CGSizeZero,NO};beginYellow(model,&drag);drag.translation=CGSizeMake(4,-40);STHUpdate(&drag,m);
  assert(STHClassify(m,CGPointMake(120,120))==4);
  STHSetup(&drag,m);
  assert(state(m).zone==ZContent&&model.hitValue==6);
  int movesBefore=moves;drag.translation=CGSizeMake(0,120);STHUpdate(&drag,m);assert(moves==movesBefore);
  STHEnd(&drag,m);

  testMinimized=YES;nativeHit=4;
  assert(STHClassify(m,CGPointMake(120,200))==4);
  STHSetup(&drag,m);STHTap(m,1);
  assert(docked==1&&!testMinimized);
  testMinimized=NO;
  for(int i=0;i<200;i++){
   nativeHit=7;testMinimized=YES;drag=(Drag){CGSizeZero,NO};
   assert(STHClassify(m,CGPointMake(21,21))==7);
   nativeHit=10;
   assert(STHClassify(m,CGPointMake(10,200))==10);
   // Full thumbnail edges remain clickable; no content inset is applied.
   assert(STHClassify(m,CGPointMake(21,21))==4);
   int prior=docked, priorEnds=ends, priorSetups=setups;
   STHSetup(&drag,m);
   if(i%2){STHTap(m,1);STHEnd(&drag,m);}else{STHEnd(&drag,m);STHTap(m,1);}
   assert(docked==prior+1&&!testMinimized&&ends==priorEnds&&setups==priorSetups);
   assert(STHClassify(m,CGPointMake(120,120))==10);
  }
  // The right-bottom middle long press returns the size AND the resting place:
  // the card is centred on the screen, and a centred card is left alone.
  // The strip sits outside the content inset, like the original yellow edge.
  testMinimized=NO;nativeHit=4;
  drag=(Drag){CGSizeZero,NO};
  assert(STHClassify(m,CGPointMake(160,418))==3);
  assert(state(m).zone==ZReset);
  int movesAt=moves;
  STHLong(m);
  assert(moves==movesAt+1);
  assert(fabs(movedBy.width-180)<.001&&fabs(movedBy.height-80)<.001);
  CGSize rest=centerDelta(CGRectMake(200,100,200,400),CGRectMake(0,0,600,600));
  assert(fabs(rest.width)<.001&&fabs(rest.height)<.001);
  CGSize empty=centerDelta(CGRectZero,CGRectMake(0,0,600,600));
  assert(empty.width==0&&empty.height==0);
  puts("Gesture dock regression: keyboard exclusion preserved except the visible minimized hit target; one restore per gesture");
 }
 return 0;
}
