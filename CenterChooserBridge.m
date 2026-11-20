#import "CenterChooserBridge.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
UIImage *STHChooserAppIcon(NSString *identifier){
 SEL selector=NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
 Method method=class_getClassMethod(UIImage.class,selector);if(!method)return nil;
 char type[8]={0};method_getArgumentType(method,3,type,8);
 if(type[0]=='i'||type[0]=='I')return ((id(*)(id,SEL,id,int,double))objc_msgSend)(UIImage.class,selector,identifier,0,UIScreen.mainScreen.scale);
 if(type[0]=='q'||type[0]=='Q')return ((id(*)(id,SEL,id,long long,double))objc_msgSend)(UIImage.class,selector,identifier,0,UIScreen.mainScreen.scale);
 return nil;
}
void STHCenterInvokeBlock(void *raw){ void (^block)(void)=(__bridge id)raw;block(); }
