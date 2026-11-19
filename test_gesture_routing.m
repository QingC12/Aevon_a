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
CGRect STHNativeRect(void *m) { return CGRectMake(20,20,200,400); }
int STHNativeClassify(void *m,CGPoint p) { return 4; }
NSUInteger STHNativeOrientation(void *m) { return 1; }
CGSize STHNativeTranslation(void *drag) { return ((Drag *)drag)->translation; }
void STHNativeMove(void *m,CGSize t) { moves++;movedBy=t; }
void STHNativeSetup(void *d,void *m) { setups++; }
void STHNativeUpdate(void *d,void *m) { updates++; }
void STHNativeEnd(void *d,void *m) {
 ends++;endHit=*hit(m);endHeld=*latch(m);
 nativeWouldClose=endHit==4&&!endHeld&&((Drag *)d)->flick;
}
void STHNativeDock(void *m) { docked++; }
void STHNativeLong(void *m) { longs++; }
void STHNativeReset(void *m) {}
void STHNativeTap(void *m,NSUInteger c) {}

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
  puts("Production yellow routing passed: immediate move, native release, no hold gate");
 }
 return 0;
}
