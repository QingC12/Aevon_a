#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
// Class name/geometry/visibility only. Callers must NEVER pass text/labels.
void STHObserveLayoutProbe(NSString *bundle);
void STHReportLayoutProbe(NSString *bundle,NSString *className,CGRect frame,unsigned flags);
