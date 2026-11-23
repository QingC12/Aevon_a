// Floating windows are hosted by SpringBoard, so the guest application cannot
// disable the system idle timer for them. This module owns the wake lease at
// the SpringBoard level and releases it as soon as the last visible card is
// gone. The coordinator path is used first; UIApplication is a bounded fallback
// for firmware builds without that private class.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#include <string.h>
#import "ScreenAwake.h"

static NSString *const reason=@"com.nx.stheno.floating-window";
static id coordinator;
static id application;
static BOOL held,applicationMode,applicationBaseline;

static const char *plain(const char *type){while(type&&*type&&strchr("rnNoORV",*type))type++;return type;}
static BOOL signature(id target,SEL selector,char result,const char *arguments){
 if(!target||![target respondsToSelector:selector])return NO;
 NSMethodSignature *s=[target methodSignatureForSelector:selector];
 if(!s||s.numberOfArguments!=strlen(arguments)+2)return NO;
 const char *r=plain(s.methodReturnType);
 if(!r||(*r!=result&&!(result=='B'&&*r=='c')))return NO;
 for(NSUInteger i=0;i<strlen(arguments);i++){
  const char *arg=plain([s getArgumentTypeAtIndex:i+2]);char want=arguments[i];
  if(!arg||(*arg!=want&&!(want=='B'&&*arg=='c')))return NO;
 }return YES;
}
static id idleCoordinator(void){
 if(coordinator)return coordinator;
 Class cls=NSClassFromString(@"SBIdleTimerGlobalCoordinator");
 if(!cls){
  dlopen("/System/Library/PrivateFrameworks/SpringBoardFramework.framework/SpringBoardFramework",RTLD_LAZY|RTLD_LOCAL);
  cls=NSClassFromString(@"SBIdleTimerGlobalCoordinator");
 }
 SEL shared=NSSelectorFromString(@"sharedInstance");
 if(!signature(cls,shared,'@',""))return nil;
 id value=((id(*)(id,SEL))objc_msgSend)(cls,shared);
 if(!signature(value,NSSelectorFromString(@"acquireIdleTimerDisableAssertionForReason:"),'v',"@"))return nil;
 if(!signature(value,NSSelectorFromString(@"releaseIdleTimerDisableAssertionForReason:"),'v',"@"))return nil;
 coordinator=value;return value;
}
static id systemApplication(void){
 if(application)return application;
 Class cls=NSClassFromString(@"UIApplication");
 SEL shared=NSSelectorFromString(@"sharedApplication");
 if(!signature(cls,shared,'@',""))return nil;
 id value=((id(*)(id,SEL))objc_msgSend)(cls,shared);
 if(!signature(value,NSSelectorFromString(@"isIdleTimerDisabled"),'B',""))return nil;
 if(!signature(value,NSSelectorFromString(@"setIdleTimerDisabled:"),'v',"B"))return nil;
 application=value;return value;
}
static void engage(void){
 if(held)return;
 @try{
  id value=idleCoordinator();
  if(value){
   ((void(*)(id,SEL,id))objc_msgSend)(value,NSSelectorFromString(@"acquireIdleTimerDisableAssertionForReason:"),reason);
   held=YES;applicationMode=NO;return;
  }
  id app=systemApplication();
  if(app){
   applicationBaseline=((BOOL(*)(id,SEL))objc_msgSend)(app,NSSelectorFromString(@"isIdleTimerDisabled"));
   ((void(*)(id,SEL,BOOL))objc_msgSend)(app,NSSelectorFromString(@"setIdleTimerDisabled:"),YES);
   held=YES;applicationMode=YES;
  }
 }@catch(NSException *error){(void)error;}
}
static void disengage(void){
 if(!held)return;
 @try{
  if(applicationMode){
   id app=application;
   SEL get=NSSelectorFromString(@"isIdleTimerDisabled"),set=NSSelectorFromString(@"setIdleTimerDisabled:");
   if(app&&signature(app,get,'B',"")&&signature(app,set,'v',"B")){
    BOOL current=((BOOL(*)(id,SEL))objc_msgSend)(app,get);
    if(current)((void(*)(id,SEL,BOOL))objc_msgSend)(app,set,applicationBaseline);
   }
  }else if(coordinator){
   ((void(*)(id,SEL,id))objc_msgSend)(coordinator,NSSelectorFromString(@"releaseIdleTimerDisableAssertionForReason:"),reason);
  }
 }@catch(NSException *error){(void)error;}
 held=NO;applicationMode=NO;applicationBaseline=NO;
}
void STHScreenAwakeUpdate(NSUInteger visibleFloatingWindows){
 if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{STHScreenAwakeUpdate(visibleFloatingWindows);});return;}
 if(visibleFloatingWindows)engage();else disengage();
}
void STHScreenAwakeSuspend(void){STHScreenAwakeUpdate(0);}
BOOL STHScreenAwakeHeld(void){return held;}
#if defined(STH_SCREEN_AWAKE_TEST)
void STHScreenAwakeResetTestState(void){
 disengage();coordinator=nil;application=nil;held=NO;applicationMode=NO;applicationBaseline=NO;
}
#endif
