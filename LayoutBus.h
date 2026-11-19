#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include "LayoutMath.h"
BOOL STHBeginLayout(NSString *bundle);
// 0 inactive/stale, 1 committed, 2 waiting for first stable snapshot.
int STHLayoutStatus(NSString *bundle);
BOOL STHPublishLayout(NSString *bundle,CGRect card,CGRect keyboard,BOOL active);
BOOL STHReadLayout(NSString *bundle,CGRect appBounds,CGRect *local,double *overlap);
void STHObserveLayout(NSString *bundle,dispatch_block_t block);
void STHReportLayout(NSString *bundle,double overlap,BOOL applied);
void STHWriteLayoutLog(NSString *line);
void STHReportNotificationFrame(NSString *bundle,CGRect scene,CGRect frame);
BOOL STHPreviewLayout(NSString *bundle,CGRect predictedCard);
BOOL STHReadPreview(NSString *bundle,CGRect physicalKeyboard,CGRect scene,CGRect *local,double *inset);
// stage:1 lifecycle,2 no editable responder,3 no safe composer,4 measured,5 moved,6 restored.
void STHReportEditor(NSString *bundle,int stage,CGRect assembly,double keyTop,double lift,unsigned rows);
BOOL STHReadLayoutUsingKeyboard(NSString *bundle,CGRect scene,CGRect measuredKeyboard,CGRect *mapped,double *inset);
