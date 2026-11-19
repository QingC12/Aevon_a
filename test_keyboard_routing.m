#define STH_KEYBOARD_TEST 1
#include <assert.h>
#include <stdio.h>
#import "Keyboard.m"

@interface Model : NSObject
@property double scale;
@property CGSize offset;
@property CGRect card;
@property NSUInteger orientation;
@end
@implementation Model
@end
static int showCalls,hideCalls,writes;
static BOOL inOriginalTransaction;
CGRect STHNativeRect(void *p) { return ((__bridge Model *)p).card; }
NSUInteger STHNativeOrientation(void *p) { return ((__bridge Model *)p).orientation; }
double STHNativeGetScale(void *p) { return ((__bridge Model *)p).scale; }
CGSize STHNativeGetOffset(void *p) { return ((__bridge Model *)p).offset; }
void STHNativeSetKeyboardGeometry(void *p,const double *v) {
 assert(inOriginalTransaction);
 Model *m=(__bridge Model *)p;
 m.scale=v[0];m.offset=CGSizeMake(v[1],v[2]);writes++;
}
void STHNativeKeyboardShow(void *p) { assert(inOriginalTransaction);showCalls++; }
void STHNativeKeyboardHide(void) { assert(inOriginalTransaction);hideCalls++; }
static Model *make(void) {
 Model *m=[Model new];m.scale=.8;m.orientation=1;
 m.card=CGRectMake(40,150,320,500);m.offset=CGSizeMake(0,20);return m;
}
static void show(Model *m,NSValue *frame) {
 STHKeyboardFocus((__bridge void *)m);
 STHKeyboardShow((__bridge void *)frame);
}
int main(void) {
 @autoreleasepool {
  inOriginalTransaction=YES;
  NSValue *frame=[NSValue valueWithRect:NSMakeRect(0,550,400,300)];
  Model *a=make();show(a,frame);
  assert(fabs(a.scale-1.0)<.00001&&owner==a&&writes==1);
  assert(fabs(a.card.size.width*(a.scale/.8)-400.0)<.00001);
  double enlarged=a.scale;
  STHKeyboardShow((__bridge void *)frame);
  assert(fabs(a.scale-enlarged)<.00001&&writes==1&&showCalls==2);
  STHKeyboardHide();assert(fabs(a.scale-.8)<.00001&&fabs(a.offset.height-20)<.001);
  STHKeyboardHide();assert(writes==2); // no duplicate restore

  show(a,frame);a.scale=.95;a.offset=CGSizeMake(12,15);
  STHKeyboardHide();assert(fabs(a.scale-.95)<.001&&fabs(a.offset.width-12)<.001);

  Model *b=make();a=make();show(a,frame);show(b,frame);
  assert(fabs(a.scale-.8)<.001&&b.scale>.8&&owner==b);
  STHKeyboardHide();assert(fabs(b.scale-.8)<.001);

  Model *offcenter=make();offcenter.card=CGRectMake(70,150,320,500);
  offcenter.offset=CGSizeMake(30,20);show(offcenter,frame);
  assert(fabs(offcenter.offset.width)<.00001);
  double displayedLeft=CGRectGetMidX(offcenter.card)+(offcenter.offset.width-30)-200;
  assert(fabs(displayedLeft)<.00001); // no left/right margin
  STHKeyboardHide();assert(fabs(offcenter.offset.width-30)<.00001);

  int before=writes;
  NSValue *hardware=[NSValue valueWithRect:NSMakeRect(0,840,400,10)];
  show(b,hardware);assert(writes==before);
  b.orientation=3;show(b,frame);assert(writes==before);
  b.orientation=1;STHKeyboardFocus((__bridge void *)b);candidateAt-=3;
  STHKeyboardShow((__bridge void *)frame);assert(writes==before);
  printf("Keyboard routing passed: %d native show, %d hide, %d geometry writes\n",showCalls,hideCalls,writes);
 }
 return 0;
}
