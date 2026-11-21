#import <Foundation/Foundation.h>
#include "LayoutMath.h"
BOOL STHPublishInputKeyboard(NSString *bundle,STHRect frame);
BOOL STHReadInputKeyboard(NSString *bundle,STHRect *frame);
void STHResetInputFocusReadEpoch(void);
void STHPublishInputFocus(NSString *bundle, BOOL active);
BOOL STHReadInputFocus(NSString *bundle);
void STHObserveInputFocus(dispatch_block_t block);
