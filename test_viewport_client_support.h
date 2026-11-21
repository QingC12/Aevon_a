#ifndef STH_CLIENT_SUPPORT_H
#define STH_CLIENT_SUPPORT_H
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
typedef NS_ENUM(NSInteger,UISceneActivationState){UISceneActivationStateForegroundActive,UISceneActivationStateForegroundInactive,UISceneActivationStateBackground,UISceneActivationStateUnattached};
typedef NS_ENUM(NSInteger,UIInterfaceOrientation){UIInterfaceOrientationUnknown,UIInterfaceOrientationPortrait};
@class UIWindow,UIWindowScene;
@interface TestSpace:NSObject
@property CGRect bounds;
-(CGRect)convertRect:(CGRect)r toCoordinateSpace:(id)space;
@end
@interface UIScreen:NSObject
@property(strong) TestSpace *coordinateSpace,*fixedCoordinateSpace;
@property CGRect bounds;
+(UIScreen *)mainScreen;
@end
@interface UIScene:NSObject
@property UISceneActivationState activationState;
@end
@interface UIWindowScene:UIScene
@property(strong) UIScreen *screen;
@property UIInterfaceOrientation interfaceOrientation;
@property(strong) TestSpace *coordinateSpace;
@property(strong) NSArray<UIWindow *> *windows;
@end
@interface UIView:NSObject
@property BOOL hidden,isFirstResponder,clipsToBounds;
@property CGFloat alpha;
@property CGRect bounds;
@property CGAffineTransform transform;
@property(strong) UIWindow *window;
@property(strong) UIView *superview;
@property(strong) NSArray<UIView *> *subviews;
-(CGRect)convertRect:(CGRect)r toCoordinateSpace:(id)space;
@end
@interface UIWindow:UIView
@property(strong) UIWindowScene *windowScene;
@end
@interface UIApplication:NSObject
@property(strong) NSSet<UIScene *> *connectedScenes;
+(UIApplication *)sharedApplication;
@end
@interface NSValue (STHVTestRect)
+(NSValue *)valueWithCGRect:(CGRect)r;
-(CGRect)CGRectValue;
@end
#define UIKeyboardWillShowNotification @"keyboard.will.show"
#define UIKeyboardDidShowNotification @"keyboard.did.show"
#define UIKeyboardWillChangeFrameNotification @"keyboard.will.change"
#define UIKeyboardDidChangeFrameNotification @"keyboard.did.change"
#define UIKeyboardWillHideNotification @"keyboard.will.hide"
#define UIKeyboardDidHideNotification @"keyboard.did.hide"
#define UIKeyboardFrameBeginUserInfoKey @"frame.begin"
#define UIKeyboardFrameEndUserInfoKey @"frame.end"
#define UIKeyboardIsLocalUserInfoKey @"local"
#define UIKeyboardAnimationDurationUserInfoKey @"duration"
#define UIKeyboardAnimationCurveUserInfoKey @"curve"
#endif
