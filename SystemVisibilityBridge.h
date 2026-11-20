#pragma once
#import <Foundation/Foundation.h>

// Posted on the main thread only when the combined block changes.
FOUNDATION_EXPORT NSNotificationName const SthenoSystemVisibilityChanged;

// The read is thread-safe. Install once, then refresh on an existing main UI tick.
FOUNDATION_EXPORT BOOL STHSystemUIBlocked(void);
FOUNDATION_EXPORT void STHInstallSystemVisibility(void);
FOUNDATION_EXPORT void STHRefreshSystemVisibility(void);
