#import <UIKit/UIKit.h>
@interface STHChooserPanel : UIViewController
@property(nonatomic,copy) NSArray<NSDictionary<NSString *,NSString *> *> *items;
@property(nonatomic,copy) void(^closed)(NSString *identifier);
- (void)showFromPoint:(CGPoint)screenPoint inScene:(UIWindowScene *)scene aboveLevel:(CGFloat)level;
- (void)dismissChoosing:(NSString *)identifier animated:(BOOL)animated;
@end
