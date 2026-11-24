#import <Foundation/Foundation.h>
#import "ViewportGeometry.h"
void STHVLog(NSString *event,NSString *bundle,NSDictionary *values);
NSDictionary *STHVRectJSON(STHVRect rect);
/* SpringBoard installs the receiving end once, on the main queue. A sandboxed
 * application cannot open the shared file, so its records are handed over this
 * port and appended verbatim by the process that can open it. */
void STHVLogInstallRelay(void);
/* Bytes already formatted as records, appended verbatim. Used by the collector
 * that copies an application container file out without the application having
 * to cooperate: a sandboxed process can neither open the shared file nor look up
 * a foreign Mach service, but it does write its own container. */
void STHVLogAppendFromFile(NSData *data);
