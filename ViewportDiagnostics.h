#import <Foundation/Foundation.h>
#import "ViewportGeometry.h"
void STHVLog(NSString *event,NSString *bundle,NSDictionary *values);
NSDictionary *STHVRectJSON(STHVRect rect);
/* SpringBoard installs the receiving end once, on the main queue. A sandboxed
 * application cannot open the shared file, so its records are handed over this
 * port and appended verbatim by the process that can open it. */
void STHVLogInstallRelay(void);
