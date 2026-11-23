// Floating windows are hosted by SpringBoard, so the guest application cannot
// disable the system idle timer for them. This module owns the wake lease at
// the SpringBoard level.
//
// acquireIdleTimerDisableAssertionForReason: returns an assertion object and
// there is no matching release method: the assertion lives exactly as long as
// that object does, and it is dropped by sending -invalidate. Demanding a
// release method rejected the coordinator on every firmware and pushed the
// lease onto UIApplication.isIdleTimerDisabled, which SpringBoard ignores, so
// the display kept dimming. The lease now owns the assertion object, verifies
// that the system still reports the idle timer disabled, and degrades to a
// bounded reset heartbeat when the private path is missing or ineffective.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#include <string.h>
#import "ScreenAwake.h"

#define STH_REASSERT_EVERY_TICKS 5
#define STH_MAX_REASSERTS 3

static NSString *const reason=@"com.nx.stheno.floating-window";
static id coordinator;
static id assertion;
static id application;
static BOOL held,applicationMode,applicationBaseline,heartbeat;
static unsigned ticks,reasserts,lastReassertTick;

static SEL named(const char *name){return NSSelectorFromString([NSString stringWithUTF8String:name]);}
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
  dlopen("/System/Library/PrivateFrameworks/SpringBoard.framework/SpringBoard",RTLD_LAZY|RTLD_LOCAL);
  cls=NSClassFromString(@"SBIdleTimerGlobalCoordinator");
 }
 if(!cls)return nil;
 id value=nil;
 SEL shared=named("sharedInstance");
 if(signature((id)cls,shared,'@',""))value=((id(*)(id,SEL))objc_msgSend)((id)cls,shared);
 if(!value){
  SEL existing=named("sharedInstanceIfExists");
  if(signature((id)cls,existing,'@',""))value=((id(*)(id,SEL))objc_msgSend)((id)cls,existing);
 }
 if(!value){
  SEL create=named("_sharedInstanceCreateIfNeeded:");
  if(signature((id)cls,create,'@',"B"))value=((id(*)(id,SEL,BOOL))objc_msgSend)((id)cls,create,YES);
 }
 if(!value)return nil;
 coordinator=value;return value;
}
static id systemApplication(void){
 if(application)return application;
 Class cls=NSClassFromString(@"UIApplication");
 SEL shared=named("sharedApplication");
 if(!signature((id)cls,shared,'@',""))return nil;
 id value=((id(*)(id,SEL))objc_msgSend)((id)cls,shared);
 if(!signature(value,named("isIdleTimerDisabled"),'B',""))return nil;
 if(!signature(value,named("setIdleTimerDisabled:"),'v',"B"))return nil;
 application=value;return value;
}
static id acquireAssertion(void){
 id value=idleCoordinator();if(!value)return nil;
 SEL acquire=named("acquireIdleTimerDisableAssertionForReason:");
 if(!signature(value,acquire,'@',"@"))return nil;
 id lease=nil;
 @try{lease=((id(*)(id,SEL,id))objc_msgSend)(value,acquire,reason);}@catch(NSException *error){(void)error;return nil;}
 return lease;
}
static BOOL timerDisabled(id value){
 SEL get=named("isIdleTimerDisabled");
 if(!signature(value,get,'B',""))return YES;
 @try{return ((BOOL(*)(id,SEL))objc_msgSend)(value,get);}@catch(NSException *error){(void)error;return YES;}
}
static BOOL resetIdleTimer(id value){
 SEL reset=named("resetIdleTimerForReason:");
 if(!signature(value,reset,'v',"@"))return NO;
 @try{((void(*)(id,SEL,id))objc_msgSend)(value,reset,reason);}@catch(NSException *error){(void)error;return NO;}
 return YES;
}
static void dropAssertion(void){
 id value=assertion;assertion=nil;
 if(!value)return;
 SEL invalidate=named("invalidate");
 if([value respondsToSelector:invalidate]){((void(*)(id,SEL))objc_msgSend)(value,invalidate);return;}
 if(!coordinator)return;
 SEL release=named("releaseIdleTimerDisableAssertionForReason:");
 if(signature(coordinator,release,'v',"@"))((void(*)(id,SEL,id))objc_msgSend)(coordinator,release,reason);
}
static void engage(void){
 if(held)return;
 @try{
  id value=idleCoordinator();
  id lease=value?acquireAssertion():nil;
  if(lease){assertion=lease;held=YES;applicationMode=NO;heartbeat=NO;return;}
  // The private path is present but refused the assertion. Resetting the idle
  // timer is a weaker, still SpringBoard-level claim: it restarts the same
  // countdown the system would otherwise let expire.
  if(value&&resetIdleTimer(value)){heartbeat=YES;held=YES;applicationMode=NO;return;}
  id app=systemApplication();
  if(app){
   applicationBaseline=((BOOL(*)(id,SEL))objc_msgSend)(app,named("isIdleTimerDisabled"));
   ((void(*)(id,SEL,BOOL))objc_msgSend)(app,named("setIdleTimerDisabled:"),YES);
   held=YES;applicationMode=YES;heartbeat=NO;
  }
 }@catch(NSException *error){(void)error;}
}
static void disengage(void){
 if(!held)return;
 @try{
  dropAssertion();
  if(applicationMode&&application){
   SEL get=named("isIdleTimerDisabled"),set=named("setIdleTimerDisabled:");
   if(signature(application,get,'B',"")&&signature(application,set,'v',"B")){
    // Never overwrite a value some other writer owns: only clear a disable
    // that is still the one this lease installed.
    if(((BOOL(*)(id,SEL))objc_msgSend)(application,get))((void(*)(id,SEL,BOOL))objc_msgSend)(application,set,applicationBaseline);
   }
  }
 }@catch(NSException *error){(void)error;}
 held=NO;applicationMode=NO;applicationBaseline=NO;heartbeat=NO;
 ticks=0;reasserts=0;lastReassertTick=0;
}
void STHScreenAwakeUpdate(NSUInteger visibleFloatingWindows){
 if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{STHScreenAwakeUpdate(visibleFloatingWindows);});return;}
 if(!visibleFloatingWindows){disengage();return;}
 if(!held){engage();return;}
 ticks++;
 if(heartbeat){
  if(coordinator)resetIdleTimer(coordinator);
  return;
 }
 if(applicationMode){
  id app=application;
  SEL get=named("isIdleTimerDisabled"),set=named("setIdleTimerDisabled:");
  if(app&&signature(app,get,'B',"")&&signature(app,set,'v',"B")&&!((BOOL(*)(id,SEL))objc_msgSend)(app,get))
   ((void(*)(id,SEL,BOOL))objc_msgSend)(app,set,YES);
  return;
 }
 // Verification only trusts a readable getter. An unreadable one leaves the
 // held assertion alone instead of stacking assertions every second.
 if(!coordinator||timerDisabled(coordinator))return;
 if(reasserts>=STH_MAX_REASSERTS){heartbeat=YES;resetIdleTimer(coordinator);return;}
 if(ticks-lastReassertTick<STH_REASSERT_EVERY_TICKS)return;
 lastReassertTick=ticks;reasserts++;
 dropAssertion();
 assertion=acquireAssertion();
}
void STHScreenAwakeSuspend(void){STHScreenAwakeUpdate(0);}
BOOL STHScreenAwakeHeld(void){return held;}
#if defined(STH_SCREEN_AWAKE_TEST)
void STHScreenAwakeResetTestState(void){
 disengage();coordinator=nil;application=nil;assertion=nil;
 held=NO;applicationMode=NO;applicationBaseline=NO;heartbeat=NO;
 ticks=0;reasserts=0;lastReassertTick=0;
}
#endif
