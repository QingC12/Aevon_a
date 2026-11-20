#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdint.h>
typedef struct {
 double scale,offsetX,offsetY,radius,iconWidth,portraitX,portraitY,damping;
 uint8_t gestureState,editing,quickSetting,showTab;
 BOOL valid;
} STHChooserRingSnapshot;
BOOL STHChooserReadRing(STHChooserRingSnapshot *out);
NSArray<NSDictionary<NSString *,NSString *> *> *STHChooserSnapshotUnpinned(void);
BOOL STHChooserSubmitFloating(NSString *identifier);
BOOL STHChooserSubmitCenterSelection(void);
void STHChooserShowFromNativeSelection(void);
void STHInstallCenterChooser(void);
void STHChooserHideBeforeCapture(void);
