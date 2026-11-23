#import <Foundation/Foundation.h>

// Holds a SpringBoard idle-timer disable assertion only while at least one
// floating window is visible. Releasing restores the exact prior state, so the
// normal auto-dim / auto-lock policy is untouched when no floating window is
// open.
void STHScreenAwakeUpdate(NSUInteger visibleFloatingWindows);
void STHScreenAwakeSuspend(void);
BOOL STHScreenAwakeHeld(void);
