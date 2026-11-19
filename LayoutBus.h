#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include "LayoutMath.h"
BOOL STHPublishLayout(NSString *bundle,CGRect card,CGRect keyboard,BOOL active);
BOOL STHReadLayout(NSString *bundle,CGRect appBounds,CGRect *local,double *overlap);
void STHObserveLayout(NSString *bundle,dispatch_block_t block);
void STHReportLayout(NSString *bundle,double overlap,BOOL applied);
void STHWriteLayoutLog(NSString *line);
void STHReportNotificationFrame(NSString *bundle,CGRect scene,CGRect frame);
