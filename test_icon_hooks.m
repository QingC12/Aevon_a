#import <Foundation/Foundation.h>
#include <assert.h>
#include <limits.h>
#import "SystemActionCatalog.h"
extern BOOL STHInstallSystemActionIconHookForClass(Class);
static NSObject *custom,*original;
static int received32;static long long received64;static double receivedScale;
NSObject *STHSystemActionIcon(NSString *identifier,double scale){(void)scale;assert(STHSystemActionForIdentifier(identifier.UTF8String));return custom;}
@interface Image32:NSObject
+ (id)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(int)format scale:(double)scale;
@end
@implementation Image32
+ (id)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(int)format scale:(double)scale{(void)identifier;received32=format;receivedScale=scale;return original;}
@end
@interface Image64:NSObject
+ (id)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(long long)format scale:(double)scale;
@end
@implementation Image64
+ (id)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(long long)format scale:(double)scale{(void)identifier;received64=format;receivedScale=scale;return original;}
@end
@interface ImageWrong:NSObject
+ (id)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(float)format scale:(double)scale;
@end
@implementation ImageWrong
+ (id)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(float)format scale:(double)scale{(void)identifier;(void)format;(void)scale;return original;}
@end
int main(void){@autoreleasepool{
 custom=[NSObject new];original=[NSObject new];
 assert(STHInstallSystemActionIconHookForClass(Image32.class));
 assert([Image32 _applicationIconImageForBundleIdentifier:@STH_SCREENSHOT_ID format:0 scale:3]==custom);
 assert([Image32 _applicationIconImageForBundleIdentifier:@STH_SCREEN_RECORDING_ID format:0 scale:2]==custom);
 assert([Image32 _applicationIconImageForBundleIdentifier:@"com.apple.mobilesafari" format:-7 scale:2]==original);assert(received32==-7&&receivedScale==2);
 assert([Image32 _applicationIconImageForBundleIdentifier:@"com.nx.stheno.action.screenshot.fake" format:1 scale:1]==original);
 assert(STHInstallSystemActionIconHookForClass(Image32.class));
 assert(STHInstallSystemActionIconHookForClass(Image64.class));
 assert([Image64 _applicationIconImageForBundleIdentifier:@STH_SCREENSHOT_ID format:0 scale:3]==custom);
 assert([Image64 _applicationIconImageForBundleIdentifier:@"ordinary.app" format:LLONG_MAX-9 scale:3]==original);assert(received64==LLONG_MAX-9&&receivedScale==3);
 assert(!STHInstallSystemActionIconHookForClass(ImageWrong.class));
 NSLog(@"Icon factory regression passed: int and 64-bit signatures; exact IDs; original App format/scale unchanged");
}return 0;}
