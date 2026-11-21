#define STH_VIEWPORT_CLIENT_TEST 1
#import <assert.h>
#import <stdio.h>
#import "ViewportClient.m"
static UIScreen *testDisplay;
static UIApplication *testApp;
@implementation TestSpace
-(CGRect)convertRect:(CGRect)r toCoordinateSpace:(id)s{return r;}
@end
@implementation UIScreen
+(UIScreen *)mainScreen{return testDisplay;}
@end
@implementation UIScene @end
@implementation UIWindowScene @end
@implementation UIView
-(CGRect)convertRect:(CGRect)r toCoordinateSpace:(id)s{return r;}
@end
@implementation UIWindow @end
@implementation UIApplication
+(UIApplication *)sharedApplication{return testApp;}
@end
@implementation NSValue (STHVTestRect)
+(NSValue *)valueWithCGRect:(CGRect)r{return [NSValue valueWithRect:NSMakeRect(r.origin.x,r.origin.y,r.size.width,r.size.height)];}
-(CGRect)CGRectValue{NSRect r=self.rectValue;return CGRectMake(r.origin.x,r.origin.y,r.size.width,r.size.height);}
@end
static STHVSnapshot layout;
static uint64_t inputOwner;
static NSMutableArray<NSNotification *> *received;
static int activeClaims,inactiveClaims;
uint64_t STHVKey(NSString *b){return 123;}
uint64_t STHVRequestOwner(void){return inputOwner;}
BOOL STHVReadLayout(NSString *b,STHVSnapshot *out){if(out)*out=layout;return YES;}
BOOL STHVPublishRequest(NSString *b,BOOL active,STHVRect diagnostic){assert(diagnostic.w==0&&diagnostic.h==0);if(active){inputOwner=123;activeClaims++;}else inactiveClaims++;return YES;}
BOOL STHVRenewRequest(NSString *b,STHVRect r){return YES;}
BOOL STHVResumeRequest(NSString *b,STHVRect r){return YES;}
void STHVPublishProbe(NSString *b,STHVRect a,STHVRect p){}
void STHVPublishClientFrames(NSString *b,STHVRect raw,STHVRect mapped,uint64_t generation){}
void STHVLog(NSString *e,NSString *b,NSDictionary *v){}
NSDictionary *STHVRectJSON(STHVRect r){return @{};}
CGRect STHVUnmodifiedScreenBounds(UIScreen *s){return s.fixedCoordinateSpace.bounds;}
static void receiver(id c,SEL s,NSNotification *n){[received addObject:n];}
static void receiverName(id c,SEL s,NSString *name,id object,NSDictionary *info){receiver(c,s,[NSNotification notificationWithName:name object:object userInfo:info]);}
static CGFloat nativeInset(id o,SEL s,UIWindowScene *scene,BOOL *minimum,BOOL ignore){return 123;}
static void send(NSString *name,CGRect raw){NSDictionary *info=@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:raw],UIKeyboardIsLocalUserInfoKey:@YES,UIKeyboardAnimationDurationUserInfoKey:@.25};post(NSNotificationCenter.defaultCenter,@selector(postNotification:),[NSNotification notificationWithName:name object:testDisplay userInfo:info]);}
static CGRect delivered(void){return [received.lastObject.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];}
int main(void){@autoreleasepool{
 testDisplay=[UIScreen new];testDisplay.fixedCoordinateSpace=[TestSpace new];testDisplay.fixedCoordinateSpace.bounds=CGRectMake(0,0,430,932);testDisplay.coordinateSpace=testDisplay.fixedCoordinateSpace;
 UIWindowScene *scene=[UIWindowScene new];scene.activationState=UISceneActivationStateForegroundActive;scene.interfaceOrientation=UIInterfaceOrientationPortrait;scene.screen=testDisplay;scene.coordinateSpace=[TestSpace new];scene.coordinateSpace.bounds=CGRectMake(0,0,430,731);
 UIWindow *window=[UIWindow new];window.windowScene=scene;window.alpha=1;scene.windows=@[window];
 UIView *field=[UIView new];field.window=window;field.isFirstResponder=YES;field.alpha=1;field.bounds=CGRectMake(0,0,300,40);field.transform=CGAffineTransformIdentity;
 window.subviews=@[field];testApp=[UIApplication new];testApp.connectedScenes=[NSSet setWithObject:scene];
 received=[NSMutableArray new];systemPost=receiver;systemPostName=receiverName;systemInset=nativeInset;
 layout=(STHVSnapshot){.card={0,100.5,430,731},.keyboard={0,590,430,342},.active=YES,.hosted=YES,.keyboardVisible=YES,.physicalGeneration=1,.serial=1};
 editingView=field;editingScene=scene;inputOwner=123;
 CGRect raw[]={ {0,774,430,158},{0,804.6666666667,430,127.3333333333},{0,835.3333333333,430,96.6666666667},{0,932,430,97} };
 for(unsigned cycle=0;cycle<200;cycle++){
  layout.active=YES;layout.keyboardVisible=YES;layout.keyboard=(STHVRect){0,590,430,342};layout.physicalGeneration++;layout.serial++;
  for(unsigned i=0;i<4;i++){
   send(i%2?UIKeyboardDidChangeFrameNotification:UIKeyboardWillChangeFrameNotification,raw[i]);
   assert(fabs(delivered().origin.y-489.5)<.001&&fabs(delivered().size.height-241.5)<.001);
   assert(fabs(inset(nil,NULL,scene,NULL,NO)-241.5)<.001);
  }
  layout.active=NO;layout.keyboardVisible=NO;layout.keyboard=(STHVRect){0};layout.physicalGeneration++;layout.serial++;hostChanged();
  [received removeAllObjects];
  for(unsigned i=0;i<4;i++){
   send(i%2?UIKeyboardDidChangeFrameNotification:UIKeyboardWillShowNotification,raw[i]);
   assert(delivered().origin.y==731&&delivered().size.height==0);
   assert(inset(nil,NULL,scene,NULL,NO)==0&&!mappedSession&&!visible);
  }
  layout.active=YES;layout.keyboardVisible=YES;layout.keyboard=(STHVRect){0,590,430,342};layout.physicalGeneration++;layout.serial++;hostChanged();
  assert(mappedSession&&visible&&fabs(inset(nil,NULL,scene,NULL,NO)-241.5)<.001);
 }
 layout.hosted=NO;layout.active=NO;layout.keyboardVisible=NO;layout.card=(STHVRect){0};layout.serial++;hostChanged();
 send(UIKeyboardWillShowNotification,raw[0]);assert(delivered().size.height==158&&inset(nil,NULL,scene,NULL,NO)==123);
 layout.hosted=YES;layout.card=(STHVRect){0,100.5,430,731};scene.coordinateSpace.bounds=CGRectMake(0,0,430,932);
 send(UIKeyboardWillShowNotification,raw[0]);assert(delivered().size.height==158&&inset(nil,NULL,scene,NULL,NO)==123);
 stopLease();assert(activeClaims>0);
 puts("Viewport32 client production hooks: 200 SB-visible/raw-drift/hide/late-app-show-change/reopen cycles; real notification delivery and inset reject stale positive data; fullscreen/non-hosted native fallback retained (UIKit stand-ins, not device rendering)");
}return 0;}
