#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <assert.h>
#include "ChooserFocusRouting.inc"
static NSMutableArray *events;
@interface TestAssertion : NSObject
@property NSString *name;
@property int invalidations;
@end
@implementation TestAssertion
- (void)invalidate{self.invalidations++;[events addObject:self.name];}
@end
@interface TestFocusController : NSObject
@property TestAssertion *scene;
@property TestAssertion *steal;
@property id expectedScene;
@property id expectedWindow;
@end
@implementation TestFocusController
- (id)lockFocusToSpringBoardWindowScene:(id)scene forReason:(id)reason{
 assert(scene==self.expectedScene&&[reason length]);[events addObject:@"lock"];return self.scene;
}
- (id)requestFocusStealingForSpringBoardWindow:(id)window forReason:(id)reason{
 assert(window==self.expectedWindow&&[reason length]);[events addObject:@"steal"];return self.steal;
}
@end
@interface WrongFocusABI : NSObject
@end
@implementation WrongFocusABI
- (NSInteger)lockFocusToSpringBoardWindowScene:(id)scene forReason:(id)reason{assert(0);return 0;}
@end
int main(void){@autoreleasepool{
 for(int i=0;i<200;i++){
  events=[NSMutableArray new];TestFocusController *c=[TestFocusController new];
  c.expectedScene=[NSObject new];c.expectedWindow=[NSObject new];
  c.scene=[TestAssertion new];c.scene.name=@"release-scene";c.steal=[TestAssertion new];c.steal.name=@"release-window";
  NSObject *token=createChooserFocusToken(c,c.expectedScene,c.expectedWindow);assert(token);
  assert(([events isEqual:@[@"lock",@"steal"]]));invalidateFocus(token);invalidateFocus(token);token=nil;
  assert(c.scene.invalidations==1&&c.steal.invalidations==1);
  assert(([events isEqual:@[@"lock",@"steal",@"release-window",@"release-scene"]]));
  events=[NSMutableArray new];c.steal=nil;
  assert(!createChooserFocusToken(c,c.expectedScene,c.expectedWindow));assert(c.scene.invalidations==2);
  c.scene=nil;events=[NSMutableArray new];assert(!createChooserFocusToken(c,c.expectedScene,c.expectedWindow));
  assert([events isEqual:@[@"lock"]]);
 }
 assert(!createChooserFocusToken([WrongFocusABI new],[NSObject new],[NSObject new]));
 puts("Chooser shell routing: 200 paired lock/steal/close and partial-failure cycles; ABI mismatch rejected");
}return 0;}
