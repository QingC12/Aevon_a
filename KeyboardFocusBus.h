#import <Foundation/Foundation.h>
void STHPublishInputFocus(NSString *bundle, BOOL active);
BOOL STHReadInputFocus(NSString *bundle);
void STHObserveInputFocus(dispatch_block_t block);
