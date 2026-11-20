#import <Foundation/Foundation.h>
#if !defined(STH_ICON_HOOK_TEST)
#import <UIKit/UIKit.h>
#else
typedef NSObject UIImage;
#endif
#import <objc/runtime.h>
#import "SystemActionCatalog.h"
extern UIImage *STHSystemActionIcon(NSString *,double);
static UIImage *(*original32)(id,SEL,NSString *,int,double);
static UIImage *(*original64)(id,SEL,NSString *,long long,double);
static UIImage *customIcon(NSString *identifier,double scale){
 if(![identifier isKindOfClass:NSString.class]||STHSystemActionForIdentifier(identifier.UTF8String)==STHSystemActionNone)return nil;
 return STHSystemActionIcon(identifier,scale);
}
static UIImage *icon32(id cls,SEL cmd,NSString *identifier,int format,double scale){
 UIImage *image=customIcon(identifier,scale);return image?:original32(cls,cmd,identifier,format,scale);
}
static UIImage *icon64(id cls,SEL cmd,NSString *identifier,long long format,double scale){
 UIImage *image=customIcon(identifier,scale);return image?:original64(cls,cmd,identifier,format,scale);
}
BOOL STHInstallSystemActionIconHookForClass(Class cls){
 SEL sel=NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
 Method m=class_getClassMethod(cls,sel);if(!m||method_getNumberOfArguments(m)!=5)return NO;
 char result[16]={0},identifier[16]={0},format[16]={0},scale[16]={0};
 method_getReturnType(m,result,sizeof(result));method_getArgumentType(m,2,identifier,sizeof(identifier));
 method_getArgumentType(m,3,format,sizeof(format));method_getArgumentType(m,4,scale,sizeof(scale));
 // The private UIKit API is int on some OS versions. 2.0.16 accepted only
 // q/Q and silently left the original missing-app placeholder in that case.
 if(result[0]!='@'||identifier[0]!='@'||scale[0]!='d')return NO;
 BOOL narrow=format[0]=='i'||format[0]=='I';BOOL wide=format[0]=='q'||format[0]=='Q';
 if(!narrow&&!wide)return NO;
 IMP current=method_getImplementation(m),replacement=narrow?(IMP)icon32:(IMP)icon64;
 if(current==replacement)return YES;
 if(narrow)original32=(void *)current;else original64=(void *)current;
 method_setImplementation(m,replacement);return YES;
}
BOOL STHInstallSystemActionIconHook(void){
#if defined(STH_ICON_HOOK_TEST)
 return NO;
#else
 return STHInstallSystemActionIconHookForClass(UIImage.class);
#endif
}
