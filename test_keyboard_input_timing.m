#define STH_KEYBOARD_TEST 1
#define STH_KEYBOARD_INPUT_TEST 1
#include <assert.h>
#include <stdio.h>
#import "Keyboard.m"

@interface Model : NSObject
@property double scale;
@property CGSize offset;
@property CGRect card;
@property NSUInteger orientation;
@property BOOL minimized;
@end
@implementation Model
@end
static int showCalls,hideCalls,writes;
static BOOL inOriginalTransaction;
CGRect STHNativeRect(void *p) { return ((__bridge Model *)p).card; }
NSUInteger STHNativeOrientation(void *p) { return ((__bridge Model *)p).orientation; }
BOOL STHNativeMinimized(void *p) { return ((__bridge Model *)p).minimized; }
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
 STHKeyboardInputFocus((__bridge void *)m);
 STHKeyboardShow((__bridge void *)frame);
}

static Model *offeredModel;
static STHRect offeredFrame;
static BOOL systemEnabled=YES;
static int preparations,layoutStarts,layoutStops;
void STHResetInputFocusReadEpoch(void){}
BOOL STHSystemActionsEnabled(void){return systemEnabled;}
void *STHCopyInputFocusedModel(void){return offeredModel.minimized?NULL:(__bridge void *)offeredModel;}
void *STHCopyInputFocusedModelWithFrame(STHRect *frame){if(frame)*frame=offeredFrame;return STHCopyInputFocusedModel();}
void STHChooserReleaseSwift(void *value){}
void STHPrepareLayoutFocus(void *model){preparations++;}
void STHStartLayout(void *model,CGRect frame){layoutStarts++;}
void STHStopLayout(void){layoutStops++;}
void STHUpdateLayout(void){}
void STHCenterRunAnimation(void (^block)(void),int style){BOOL was=inOriginalTransaction;inOriginalTransaction=YES;block();inOriginalTransaction=was;}
static void nativeShow(NSValue *frame){inOriginalTransaction=YES;STHKeyboardShow((__bridge void *)frame);inOriginalTransaction=NO;}
static void nativeHide(void){inOriginalTransaction=YES;STHKeyboardHide();inOriginalTransaction=NO;}
int main(void){@autoreleasepool{
 NSValue *frame=[NSValue valueWithRect:NSMakeRect(0,550,400,300)];
 for(int i=0;i<200;i++){
  Model *a=make();offeredModel=nil;offeredFrame=(STHRect){0,0,0,0};
  int before=showCalls;nativeShow(frame);assert(showCalls==before+1&&!owner);
  offeredModel=a;offeredFrame=(STHRect){0,550,400,300};before=showCalls;inputOwnerChanged();
  assert(owner==a&&a.scale>.8&&showCalls==before); // No DidShow or second native callback.
  int targetWrites=writes;inputOwnerChanged();assert(writes==targetWrites&&showCalls==before);
  nativeHide();assert(fabs(a.scale-.8)<.001);
  offeredModel=a;offeredFrame=(STHRect){0,0,0,0};targetWrites=writes;inputOwnerChanged();assert(!owner&&writes==targetWrites);
  offeredFrame=(STHRect){0,550,400,300};before=showCalls;inputOwnerChanged();assert(owner==a&&showCalls==before);
  targetWrites=writes;nativeShow(frame);assert(writes==targetWrites&&showCalls==before+1);
  nativeHide();assert(fabs(a.scale-.8)<.001&&fabs(a.offset.height-20)<.001);
  inputOwnerChanged();assert(owner==a);inOriginalTransaction=YES;a.minimized=YES;STHKeyboardModelDidMinimize((__bridge void *)a);inOriginalTransaction=NO;
  targetWrites=writes;inputOwnerChanged();assert(!owner&&writes==targetWrites);
  a.minimized=NO;inOriginalTransaction=YES;STHKeyboardSetLocalInput(YES);inOriginalTransaction=NO;
  targetWrites=writes;inputOwnerChanged();assert(!owner&&writes==targetWrites);STHKeyboardSetLocalInput(NO);
  offeredModel=nil;offeredFrame=(STHRect){0,0,0,0};
 }
 puts("Keyboard Will timing: 200 frame-first/claim-first cycles; target set inline, zero native replay, one saved snapshot, dock/local input isolated");
}return 0;}
