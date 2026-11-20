#import <Foundation/Foundation.h>
// User-invoked system backend only. Never starts on load, preference changes,
// list rendering or state queries. Completion is dispatched on main.
void STHCapturePerform(unsigned action,void(^completion)(NSError *error));
BOOL STHCaptureRecordingActive(void);
