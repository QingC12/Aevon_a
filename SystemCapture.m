#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#include <string.h>
#if !defined(STH_CAPTURE_TEST)
#import <UIKit/UIKit.h>
#endif
#import "SystemCapture.h"
static const char *plain(const char *type){while(type&&*type&&strchr("rnNoORV",*type))type++;return type;}
static BOOL signature(id target,SEL selector,char result,const char *arguments){
 if(!target||![target respondsToSelector:selector])return NO;
 NSMethodSignature *s=[target methodSignatureForSelector:selector];if(!s||s.numberOfArguments!=strlen(arguments)+2)return NO;
 const char *r=plain(s.methodReturnType);if(!r||(*r!=result&&!(result=='B'&&*r=='c')))return NO;
 for(NSUInteger i=0;i<strlen(arguments);i++){
  const char *arg=plain([s getArgumentTypeAtIndex:i+2]);char want=arguments[i];
  if(!arg||(*arg!=want&&!(want=='B'&&*arg=='c')))return NO;
 }return YES;
}
static NSError *failure(NSInteger code,NSString *description){return [NSError errorWithDomain:@"SthenoSystemCapture" code:code userInfo:@{NSLocalizedDescriptionKey:description}];}
static void finish(void(^completion)(NSError *),NSError *error){
 if(completion)dispatch_async(dispatch_get_main_queue(),^{completion(error);});
}
static id recorder(void){
 Class cls=NSClassFromString(@"RPScreenRecorder");
#if !defined(STH_CAPTURE_TEST)
 if(!cls){dlopen("/System/Library/Frameworks/ReplayKit.framework/ReplayKit",RTLD_LAZY|RTLD_LOCAL);cls=NSClassFromString(@"RPScreenRecorder");}
#endif
 SEL shared=NSSelectorFromString(@"sharedRecorder");
 return signature(cls,shared,'@',"")?((id(*)(id,SEL))objc_msgSend)(cls,shared):nil;
}
static BOOL flag(id object,NSString *name,BOOL *value){
 SEL selector=NSSelectorFromString(name);if(!signature(object,selector,'B',""))return NO;
 *value=((BOOL(*)(id,SEL))objc_msgSend)(object,selector);return YES;
}
BOOL STHCaptureRecordingActive(void){
 id r=recorder();BOOL active=NO,system=NO;
 return flag(r,@"isRecording",&active)&&flag(r,@"systemRecording",&system)&&active&&system;
}
static void awaitState(id r,BOOL wanted,unsigned remaining,void(^completion)(NSError *)){
 BOOL active=NO,system=NO;
 if(flag(r,@"isRecording",&active)&&flag(r,@"systemRecording",&system)){
  if((wanted&&active&&system)||(!wanted&&!active)){finish(completion,nil);return;}
 }
 if(!remaining){finish(completion,failure(7,wanted?@"系统未确认开始录屏，请检查系统限制或录屏提示后重试。":@"系统未确认停止录屏，请使用系统录屏状态入口检查。"));return;}
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.25*NSEC_PER_SEC)),dispatch_get_main_queue(),^{awaitState(r,wanted,remaining-1,completion);});
}
void STHCapturePerform(unsigned action,void(^completion)(NSError *)){
 if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{STHCapturePerform(action,completion);});return;}
 @try{
  if(action==1){
#if defined(STH_CAPTURE_TEST)
   id app=((id(*)(id,SEL))objc_msgSend)(NSClassFromString(@"STHMockApplication"),NSSelectorFromString(@"sharedApplication"));
#else
   id app=UIApplication.sharedApplication;
#endif
   SEL take=NSSelectorFromString(@"takeScreenshot");
   if(signature(app,take,'v',"")){((void(*)(id,SEL))objc_msgSend)(app,take);finish(completion,nil);return;}
   SEL manager=NSSelectorFromString(@"screenshotManager");
   id m=signature(app,manager,'@',"")?((id(*)(id,SEL))objc_msgSend)(app,manager):nil;
   SEL save=NSSelectorFromString(@"saveScreenshots");
   if(signature(m,save,'v',"")){((void(*)(id,SEL))objc_msgSend)(m,save);finish(completion,nil);return;}
   finish(completion,failure(1,@"当前系统未提供可用的原生截图接口。"));return;
  }
  if(action!=2){finish(completion,failure(2,@"未知系统功能。"));return;}
  id r=recorder();BOOL active=NO,system=NO;
  if(!flag(r,@"isRecording",&active)||!flag(r,@"systemRecording",&system)){
   finish(completion,failure(3,@"当前系统录屏状态接口不可用。"));return;
  }
  if(active){
   if(!system){finish(completion,failure(4,@"录制正由其他会话使用，请先停止该会话。"));return;}
   SEL stop=NSSelectorFromString(@"stopSystemRecording:");
   if(!signature(r,stop,'v',"@")){finish(completion,failure(5,@"当前系统未提供可用的系统录屏停止接口。"));return;}
   // Use the native system stop/save workflow. A nil optional handler avoids
   // guessing private completion block ABI and does not export a raw movie.
   ((void(*)(id,SEL,id))objc_msgSend)(r,stop,nil);awaitState(r,NO,40,completion);return;
  }
  for(NSString *key in @[@"screenRecordingAllowed",@"screenRecordingSupportedOnDevice"]){
   BOOL allowed=YES;if(flag(r,key,&allowed)&&!allowed){finish(completion,failure(6,@"系统当前不允许录屏，请检查设备限制。"));return;}
  }
  SEL start=NSSelectorFromString(@"startSystemRecordingWithMicrophoneEnabled:handler:");
  if(signature(r,start,'v',"B@")){
   ((void(*)(id,SEL,BOOL,id))objc_msgSend)(r,start,NO,nil);
  }else{
   SEL legacy=NSSelectorFromString(@"startRecordingWithMicrophoneEnabled:windowToRecord:systemRecording:handler:");
   if(!signature(r,legacy,'v',"B@B@")){finish(completion,failure(8,@"当前系统未提供可用的系统级录屏接口。"));return;}
   ((void(*)(id,SEL,BOOL,id,BOOL,id))objc_msgSend)(r,legacy,NO,nil,YES,nil);
  }
  // NEVER fall back to in-app recording, set consent flags, or enable mic.
  awaitState(r,YES,40,completion);
 }@catch(NSException *e){finish(completion,failure(9,[NSString stringWithFormat:@"系统操作未完成：%@",e.reason?:@"未知错误"]));}
}
