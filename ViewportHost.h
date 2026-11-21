#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
void STHViewportSetLocalInput(BOOL active);
void STHViewportModelMinimized(void *model);
void STHViewportModelChanged(void *model);
BOOL STHViewportKeyboardExcludes(CGPoint point);
void STHViewportPhysicalWill(CGRect frame,BOOL hiding);
