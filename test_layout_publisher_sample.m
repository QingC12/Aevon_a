#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#include <assert.h>
#include "LayoutSettle.h"
@interface UIScreen : NSObject
@property CGRect bounds;
+ (instancetype)mainScreen;
@end
@implementation UIScreen
+ (instancetype)mainScreen{static UIScreen *s;if(!s){s=[UIScreen new];s.bounds=CGRectMake(0,0,400,850);}return s;}
@end
static id observedModel;
static NSString *observedBundle;
static STHLayoutSettle settling;
static CGRect keyboardFrame,cardFrame,fallbackKeys;
static CFTimeInterval lastHeartbeat;
static int refreshes,cardReads,hierarchyWalks,publishes,nextSamples;
static STHRect rr(CGRect r){return (STHRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
static BOOL usable(CGRect r,CGRect screen){return STHFiniteRect(rr(r))&&r.size.width>=screen.size.width*.7&&r.size.height>=60&&r.size.height<screen.size.height*.7&&fabs(CGRectGetMaxY(r)-CGRectGetMaxY(screen))<=10;}
void STHNativeRefreshGeometry(void *model){assert(model==(__bridge void *)observedModel);refreshes++;}
CGRect STHNativeRect(void *model){cardReads++;return cardFrame;}
static CGRect physicalKeys(void){hierarchyWalks++;return fallbackKeys;}
BOOL STHPublishLayout(NSString *bundle,CGRect card,CGRect keys,BOOL active){assert(active&&[bundle isEqualToString:observedBundle]);publishes++;return YES;}
static void tick(void){nextSamples++;}
#include "LayoutPublisherSample.inc"
static void begin(void){
 observedModel=[NSObject new];observedBundle=@"stheno.layout.sample";
 cardFrame=CGRectMake(0,100,400,650);keyboardFrame=CGRectMake(0,550,400,300);fallbackKeys=keyboardFrame;
 STHSettleBegin(&settling,CACurrentMediaTime());refreshes=cardReads=hierarchyWalks=publishes=nextSamples=0;
}
int main(void){@autoreleasepool{
 for(int i=0;i<200;i++){
  begin();STHUpdateLayout();
  assert(refreshes==1&&cardReads==1&&hierarchyWalks==0&&publishes==1&&nextSamples==0&&settling.haveCommitted);
  STHUpdateLayout();assert(refreshes==1&&nextSamples==1); // Only the next scheduled path samples again.
  begin();keyboardFrame=CGRectNull;STHUpdateLayout();
  assert(refreshes==1&&cardReads==1&&hierarchyWalks==1&&publishes==1&&nextSamples==0);
  begin();keyboardFrame=CGRectNull;fallbackKeys=CGRectNull;STHUpdateLayout();
  assert(refreshes==1&&hierarchyWalks==1&&!publishes&&!nextSamples&&!settling.haveCommitted);
  begin();cardFrame=CGRectZero;STHUpdateLayout();assert(refreshes==1&&!publishes&&!nextSamples);
 }
 puts("Layout first frame: 200 valid/fallback/not-ready cases; one geometry refresh, no redundant inline tick or known-frame hierarchy walk");
}return 0;}
