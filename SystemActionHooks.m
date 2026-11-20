#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "SystemActionCatalog.h"

extern UIImage *STHSystemActionIcon(NSString *,CGFloat);
static UIImage *(*originalApplicationIcon)(id,SEL,NSString *,NSInteger,CGFloat);
static UIImage *applicationIcon(id cls,SEL cmd,NSString *identifier,NSInteger format,CGFloat scale){
 if([identifier isKindOfClass:NSString.class]&&STHSystemActionForIdentifier(identifier.UTF8String)!=STHSystemActionNone){
  UIImage *icon=STHSystemActionIcon(identifier,scale);if(icon)return icon;
 }
 return originalApplicationIcon(cls,cmd,identifier,format,scale);
}
BOOL STHInstallSystemActionIconHook(void){
 SEL selector=NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
 Method method=class_getClassMethod(UIImage.class,selector);
 if(!method||method_getNumberOfArguments(method)!=5)return NO;
 char result[16]={0},identifier[16]={0},format[16]={0},scale[16]={0};
 method_getReturnType(method,result,sizeof(result));
 method_getArgumentType(method,2,identifier,sizeof(identifier));
 method_getArgumentType(method,3,format,sizeof(format));
 method_getArgumentType(method,4,scale,sizeof(scale));
 if(result[0]!='@'||identifier[0]!='@'||!(format[0]=='q'||format[0]=='Q')||scale[0]!='d')return NO;
 IMP current=method_getImplementation(method);
 if(current==(IMP)applicationIcon)return YES;
 originalApplicationIcon=(void *)current;
 method_setImplementation(method,(IMP)applicationIcon);return YES;
}
