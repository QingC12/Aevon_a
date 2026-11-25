#import <Foundation/Foundation.h>
#import "ViewportGeometry.h"
/* The keyboard evidence switch. Every recorder below still exists and is still
 * wired into the same places; this one line decides whether any of them runs.
 * A deployed build keeps it at 0 because the keyboard path is frozen, and a
 * diagnostic build sets it to 1 and nothing else. When it is 0 the hot paths
 * return before they build a dictionary, open a file or start a timer, so a
 * shipped build pays one predictable branch and no disk traffic at all. */
#ifndef STH_DIAGNOSTICS
#define STH_DIAGNOSTICS 0
#endif
static inline BOOL STHVDiagnosticsEnabled(void){return STH_DIAGNOSTICS!=0;}
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
