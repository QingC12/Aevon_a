#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include "LayoutMath.h"
BOOL STHBeginLayout(NSString *bundle);
// 0 inactive/stale, 1 committed, 2 waiting for first stable snapshot.
int STHLayoutStatus(NSString *bundle);
BOOL STHPublishLayout(NSString *bundle,CGRect card,CGRect keyboard,BOOL active);
BOOL STHReadLayout(NSString *bundle,CGRect appBounds,CGRect *local,double *overlap);
void STHObserveLayout(NSString *bundle,dispatch_block_t block);
BOOL STHPreviewLayout(NSString *bundle,CGRect predictedCard);
BOOL STHReadPreview(NSString *bundle,CGRect physicalKeyboard,CGRect scene,CGRect *local,double *inset);
BOOL STHReadLayoutUsingKeyboard(NSString *bundle,CGRect scene,CGRect measuredKeyboard,CGRect *mapped,double *inset);
BOOL STHReadPhysicalLayout(NSString *bundle,CGRect *card,CGRect *keyboard);
