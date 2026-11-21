#import <UIKit/UIKit.h>
#import "Chooser.h"
#import "CenterChooserBridge.h"
void STHCenterRunAnimation(void (^block)(void),int easing);
UIImage *STHAppChooserIcon(CGFloat scale);
UIImage *STHChooserAppIcon(NSString *identifier);
BOOL STHSystemActionsEnabled(void);
BOOL STHSystemActionDismissRingNative(void);
BOOL STHSystemActionHideQuickSettingNative(void);
BOOL STHSystemUIBlocked(void);
void STHRefreshSystemVisibility(void);
void STHRegisterSthenoSurface(UIView *view);
int64_t STHDockCount(void);
BOOL STHDockRead(int64_t index,uintptr_t *key,int32_t *side,double *height);
void STHDockApply(uintptr_t key,double center);
double STHDockTop(void);
double STHDockBottom(void);

UIWindowScene * _Nullable STHChooserInputScene(UIWindowScene *renderScene);
UIWindow * _Nullable STHCreateChooserInputWindow(UIWindowScene *scene);
NSObject * _Nullable STHAcquireChooserKeyboardFocus(UIWindow *window);
void STHReleaseChooserKeyboardFocus(NSObject *assertion);
void STHKeyboardSetLocalInput(BOOL active);
