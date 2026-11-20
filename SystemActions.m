#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "SystemActionCatalog.h"
#import "SystemActionGate.h"
#import "SystemCapture.h"
extern BOOL STHSystemActionRuntimeReady(void);
extern BOOL STHSystemActionsEnabled(void);
extern BOOL STHInstallSystemActionIconHook(void);
extern void *STHSystemCopyModelIdentifier(void *);
extern BOOL STHSystemActionDismissRingNative(void);
extern BOOL STHSystemActionHideQuickSettingNative(void);
extern void STHInstallCenterChooser(void);
extern void STHChooserHideBeforeCapture(void);
static STHSystemActionGate gate;
static UIWindow *errorWindow;

static void showError(NSError *error){
 if(!error)return;

 if(errorWindow)return;
 UIWindowScene *scene=nil;
 for(UIScene *candidate in UIApplication.sharedApplication.connectedScenes)
  if([candidate isKindOfClass:UIWindowScene.class]&&candidate.activationState==UISceneActivationStateForegroundActive){scene=(id)candidate;break;}
 errorWindow=scene?[[UIWindow alloc] initWithWindowScene:scene]:[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
 errorWindow.frame=UIScreen.mainScreen.bounds;errorWindow.windowLevel=UIWindowLevelAlert+1;
 UIViewController *host=[UIViewController new];host.view.backgroundColor=UIColor.clearColor;
 errorWindow.rootViewController=host;
 UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Stheno 系统功能" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
 [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(UIAlertAction *unused){(void)unused;errorWindow.hidden=YES;errorWindow=nil;}]];
 [errorWindow makeKeyAndVisible];[host presentViewController:alert animated:YES completion:nil];
}
static void execute(STHSystemAction action){
 if(!STHSystemActionsEnabled())return;
 if(!STHSystemActionBegin(&gate,CACurrentMediaTime()))return;
 uint64_t generation=gate.generation;
 STHChooserHideBeforeCapture();
 STHSystemActionDismissRingNative();
 STHSystemActionHideQuickSettingNative();
 // Original collapse animation is 0.15s. Capture only AFTER it is off-screen,
 // not inside the selection's native SwiftUI animation/scene transaction.
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.35*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  STHCapturePerform((unsigned)action,^(NSError *error){
   dispatch_async(dispatch_get_main_queue(),^{
    if(STHSystemActionFinish(&gate,generation))showError(error);
   });
  });
 });
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(20*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  if(STHSystemActionFinish(&gate,generation))showError([NSError errorWithDomain:@"SthenoSystemAction" code:20 userInfo:@{NSLocalizedDescriptionKey:@"系统操作仍未返回，请先检查系统录屏状态后重试。"}]);
 });
}
// Called at native ring admission, BEFORE the App enters _floatings, and at
// presentation as a second guard. Exact IDs always consume the request so a
// failed/unsupported action is never sent to SpringBoard's app launcher.
BOOL STHSystemActionPresent(void *model){
 if(!model||!STHSystemActionRuntimeReady())return NO;
 NSString *identifier=CFBridgingRelease(STHSystemCopyModelIdentifier(model));
 STHSystemAction action=STHSystemActionForIdentifier(identifier.UTF8String);
 if(action==STHSystemActionNone)return NO;
 dispatch_async(dispatch_get_main_queue(),^{execute(action);});return YES;
}
__attribute__((constructor)) static void installSystemActions(void){
 if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"])return;
 if(!STHSystemActionRuntimeReady())return;
 (void)STHInstallSystemActionIconHook();
 extern void STHInstallSystemVisibility(void),STHInstallDockQueue(void);
 STHInstallSystemVisibility();STHInstallDockQueue();
 STHInstallCenterChooser();
}
