#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
void STHVObserveApplicationLaunch(NSBundle *bundle,NSNotificationCenter *center,
                                NSArray<NSString *> *events,dispatch_block_t install);
