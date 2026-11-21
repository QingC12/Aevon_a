#ifndef STH_VIEWPORT_PROCESS_H
#define STH_VIEWPORT_PROCESS_H
#import <Foundation/Foundation.h>
/* Foundation metadata only: safe before UIApplication exists. Loading the
 * library in a UIKit process does not authorize installing application hooks. */
static inline BOOL STHVApplicationBundleAllowed(NSBundle *bundle){
 if(!bundle)return NO;
 NSString *identifier=bundle.bundleIdentifier,*path=bundle.bundlePath;
 NSDictionary *info=bundle.infoDictionary;
 if(!identifier.length||![info[@"CFBundlePackageType"] isEqual:@"APPL"]||
    info[@"NSExtension"]||![path.pathExtension.lowercaseString isEqual:@"app"])return NO;
 for(NSString *component in path.pathComponents){
  NSString *extension=component.pathExtension.lowercaseString;
  if([extension isEqual:@"appex"]||[extension isEqual:@"xpc"])return NO;
 }
 if([identifier isEqual:@"com.apple.springboard"]||[identifier isEqual:@"com.apple.Spotlight"]||
    [identifier isEqual:@"com.apple.UIKit.remote-keyboard"]||
    [identifier hasPrefix:@"com.apple.WidgetKit."]||[identifier hasPrefix:@"com.apple.widgetkit."])return NO;
 return YES;
}
#endif
