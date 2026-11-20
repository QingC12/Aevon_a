#import <Foundation/Foundation.h>
#import "SystemCapture.h"
#include <assert.h>
static BOOL recording,systemSession,allowed=YES,badStart,missingRecorder,badScreenshot;
static unsigned screenshots,starts,stops;
@interface RPScreenRecorder:NSObject
+ (id)sharedRecorder;
- (BOOL)isRecording;
- (BOOL)systemRecording;
- (BOOL)screenRecordingAllowed;
- (BOOL)screenRecordingSupportedOnDevice;
- (void)startSystemRecordingWithMicrophoneEnabled:(BOOL)mic handler:(id)handler;
- (void)stopSystemRecording:(id)handler;
@end
@implementation RPScreenRecorder
+ (id)sharedRecorder{static id r;static dispatch_once_t once;dispatch_once(&once,^{r=[self new];});return missingRecorder?nil:r;}
- (BOOL)isRecording{return recording;}
- (BOOL)systemRecording{return systemSession;}
- (BOOL)screenRecordingAllowed{return allowed;}
- (BOOL)screenRecordingSupportedOnDevice{return YES;}
- (void)startSystemRecordingWithMicrophoneEnabled:(BOOL)mic handler:(id)handler{assert(!mic&&!handler);starts++;recording=YES;systemSession=YES;}
- (void)stopSystemRecording:(id)handler{assert(!handler);stops++;recording=NO;}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector{
 if(badStart&&selector==@selector(startSystemRecordingWithMicrophoneEnabled:handler:))return [NSMethodSignature signatureWithObjCTypes:"q@:B@?"];
 return [super methodSignatureForSelector:selector];
}
@end
@interface STHMockApplication:NSObject
+ (id)sharedApplication;
- (void)takeScreenshot;
@end
@implementation STHMockApplication
+ (id)sharedApplication{static id a;static dispatch_once_t once;dispatch_once(&once,^{a=[self new];});return a;}
- (void)takeScreenshot{screenshots++;}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector{
 if(badScreenshot&&selector==@selector(takeScreenshot))return [NSMethodSignature signatureWithObjCTypes:"q@:"];
 return [super methodSignatureForSelector:selector];
}
@end
static NSError *perform(unsigned action){
 __block BOOL done=NO;__block NSError *failure=nil;
 STHCapturePerform(action,^(NSError *error){assert(NSThread.isMainThread);failure=error;done=YES;});
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];
 while(!done&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
 assert(done);return failure;
}
int main(void){@autoreleasepool{
 assert(!starts&&!stops&&!screenshots);assert(!STHCaptureRecordingActive());
 assert(!perform(1));assert(screenshots==1&&!starts&&!stops);
 assert(!perform(2));assert(recording&&systemSession&&starts==1&&STHCaptureRecordingActive());
 assert(!perform(2));assert(!recording&&stops==1&&!STHCaptureRecordingActive());
 recording=YES;systemSession=NO;assert(perform(2).code==4);assert(stops==1);
 recording=NO;allowed=NO;assert(perform(2).code==6);assert(starts==1);allowed=YES;
 badStart=YES;assert(perform(2).code==8);assert(starts==1);badStart=NO;
 missingRecorder=YES;assert(perform(2).code==3);missingRecorder=NO;
 badScreenshot=YES;assert(perform(1).code==1);assert(screenshots==1);badScreenshot=NO;
 assert(perform(99).code==2);
 NSLog(@"System capture mock tests passed: exact typed APIs, native system start/stop, mic off, no load capture, incompatible selectors rejected, existing non-system session untouched");
}return 0;}
