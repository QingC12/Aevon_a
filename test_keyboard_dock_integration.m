#define STH_ROUTING_TEST 1
#define STH_KEYBOARD_TEST 1
#import <objc/runtime.h>
#include <assert.h>
#include <stdio.h>
#import "Gesture.m"
#import "Keyboard.m"

@interface DockTestModel : NSObject
@property unsigned char hitValue;
@property unsigned char latchValue;
@property unsigned char phaseValue;
@property BOOL minimized;
@property double scale;
@property CGSize offset;
@end
@implementation DockTestModel
@end
typedef struct { CGSize translation; } DockTestDrag;
static BOOL keyboardExclusion;
static int restorations, geometryWrites;
NSUInteger STHTestOffset(uintptr_t a){
 const char *key=a==0xf7920?"_hitValue":a==0xf7928?"_latchValue":"_phaseValue";
 return ivar_getOffset(class_getInstanceVariable(DockTestModel.class,key));
}
BOOL STHNativeMinimized(void *p){return ((__bridge DockTestModel *)p).minimized;}
void STHNativeSetMinimized(void *p,BOOL v){((__bridge DockTestModel *)p).minimized=v;}
NSUInteger STHNativeOrientation(void *p){return 1;}
CGRect STHNativeRect(void *p){return STHNativeMinimized(p)?CGRectMake(20,600,40,80):CGRectMake(40,150,320,500);}
int STHNativeClassify(void *p,CGPoint at){return keyboardExclusion?10:4;}
CGSize STHNativeTranslation(void *p){return ((DockTestDrag *)p)->translation;}
void STHNativeSetup(void *p,void *m){}
void STHNativeUpdate(void *p,void *m){}
void STHNativeEnd(void *p,void *m){}
void STHNativeMove(void *p,CGSize d){}
void STHNativeLong(void *p){}
void STHNativeReset(void *p){}
void STHNativeTap(void *p,NSUInteger n){}
void STHNativeDock(void *p){
 DockTestModel *m=(__bridge DockTestModel *)p;
 m.minimized=!m.minimized;
 if(m.minimized)STHKeyboardModelDidMinimize(p);else restorations++;
}
double STHNativeGetScale(void *p){return ((__bridge DockTestModel *)p).scale;}
CGSize STHNativeGetOffset(void *p){return ((__bridge DockTestModel *)p).offset;}
void STHNativeSetKeyboardGeometry(void *p,const double *g){
 DockTestModel *m=(__bridge DockTestModel *)p;
 m.scale=g[0];m.offset=CGSizeMake(g[1],g[2]);geometryWrites++;
}
void STHNativeKeyboardShow(void *p){keyboardExclusion=YES;}
void STHNativeKeyboardHide(void){keyboardExclusion=NO;}
int main(void){@autoreleasepool{
 NSValue *frame=[NSValue valueWithRect:NSMakeRect(0,550,400,300)];
 for(int cycle=0;cycle<200;cycle++){
  DockTestModel *model=[DockTestModel new];void *m=(__bridge void *)model;
  model.scale=.8;model.offset=CGSizeMake(0,20);
  STHKeyboardInputFocus(m);STHKeyboardShow((__bridge void *)frame);
  assert(owner==model&&model.scale>.8);
  STHNativeDock(m); // The original native transaction notifies dock reconciliation.
  assert(model.minimized&&!owner&&!candidate&&fabs(model.scale-.8)<.001);
  int writes=geometryWrites;
  STHKeyboardShow((__bridge void *)frame); // Late keyboard frame must not reclaim this card.
  assert(!owner&&!candidate&&geometryWrites==writes);
  assert(STHClassify(m,CGPointMake(10,640))==10);
  assert(STHClassify(m,CGPointMake(40,640))==4);
  DockTestDrag drag={CGSizeZero};STHSetup(&drag,m);
  int before=restorations;
  if(cycle%2){STHTap(m,1);STHEnd(&drag,m);}else{STHEnd(&drag,m);STHTap(m,1);}
  assert(!model.minimized&&restorations==before+1);
  STHKeyboardHide();
  assert(STHClassify(m,CGPointMake(120,220))==6);
  STHSetup(&drag,m);STHEnd(&drag,m);
 }
 puts("Keyboard/dock production integration: 200 show-dock-late-frame-restore cycles; normal content still routes correctly");
}return 0;}
