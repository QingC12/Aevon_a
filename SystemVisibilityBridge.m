#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <stdatomic.h>
#import "SystemVisibilityBridge.h"
#import "VisibilityPolicy.h"
NSNotificationName const SthenoSystemVisibilityChanged=@"SthenoSystemVisibilityChanged";
static atomic_bool blocked;
static STHVisibilityPolicy policy;
static NSMutableSet *hooked;
static char registered;
static CFTimeInterval nextRefresh;
@interface STHSurfaceVisibility:NSObject {
 @public STHHiddenIntent intent;
}
@end
@implementation STHSurfaceVisibility @end
static NSMapTable<UIView *,STHSurfaceVisibility *> *surfaces;
BOOL STHSystemUIBlocked(void){return atomic_load(&blocked);}
static BOOL readFlag(id object,NSString *name,BOOL *value){
 SEL sel=NSSelectorFromString(name);NSMethodSignature *s=[object methodSignatureForSelector:sel];
 if(!s||![object respondsToSelector:sel]||s.numberOfArguments!=2||(s.methodReturnType[0]!='B'&&s.methodReturnType[0]!='c'))return NO;
 *value=((BOOL(*)(id,SEL))objc_msgSend)(object,sel);return YES;
}
static BOOL readSource(NSString *name,NSArray<NSString *> *flags,BOOL *visible){
 Class cls=NSClassFromString(name);SEL sel=NSSelectorFromString(@"sharedInstanceIfExists");
 if(![cls respondsToSelector:sel])return NO;
 NSMethodSignature *signature=[cls methodSignatureForSelector:sel];
 if(!signature||signature.numberOfArguments!=2||signature.methodReturnType[0]!='@')return NO;
 id object=((id(*)(id,SEL))objc_msgSend)(cls,sel);
 if(!object){*visible=NO;return YES;}
 BOOL allKnown=YES,any=NO;
 for(NSString *flag in flags){BOOL value=NO;BOOL known=readFlag(object,flag,&value);allKnown&=known;any|=known&&value;}
 *visible=any;return any||allKnown;
}
static void forceHidden(UIView *view,STHSurfaceVisibility *state,BOOL value){
 state->intent.forcedDepth++;
 @try{view.hidden=value;}@finally{state->intent.forcedDepth--;}
}
static void apply(BOOL value){
 BOOL previous=atomic_exchange(&blocked,value);if(previous==value)return;
 for(UIView *view in surfaces.keyEnumerator.allObjects){
  STHSurfaceVisibility *state=[surfaces objectForKey:view];
  forceHidden(view,state,value?YES:state->intent.desired);
 }
 [NSNotificationCenter.defaultCenter postNotificationName:SthenoSystemVisibilityChanged object:nil];
}
static void event(unsigned bit,BOOL value){
 if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{event(bit,value);});return;}
 STHVisibilityEvent(&policy,bit,value,CACurrentMediaTime());apply(policy.active!=0);
 nextRefresh=0;
 dispatch_async(dispatch_get_main_queue(),^{STHRefreshSystemVisibility();});
}
void STHRegisterSthenoSurface(UIView *view){
 if(!view||objc_getAssociatedObject(view,&registered))return;
 if(!surfaces)surfaces=[NSMapTable weakToStrongObjectsMapTable];
 STHSurfaceVisibility *state=[STHSurfaceVisibility new];state->intent.desired=view.hidden;
 objc_setAssociatedObject(view,&registered,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[surfaces setObject:state forKey:view];
 Class cls=view.class;if(!hooked)hooked=[NSMutableSet set];NSString *name=NSStringFromClass(cls);
 if(![hooked containsObject:name]){
  [hooked addObject:name];SEL selector=@selector(setHidden:);Method method=class_getInstanceMethod(cls,selector);IMP original=method_getImplementation(method);
  IMP replacement=imp_implementationWithBlock(^(UIView *target,BOOL value){
   STHSurfaceVisibility *saved=objc_getAssociatedObject(target,&registered);
   if(!saved){((void(*)(id,SEL,BOOL))original)(target,selector,value);return;}
   BOOL actual=STHHiddenSetterBegin(&saved->intent,value,STHSystemUIBlocked());
   @try{((void(*)(id,SEL,BOOL))original)(target,selector,actual);}
   @finally{STHHiddenSetterEnd(&saved->intent);}
  });
  if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method)))method_setImplementation(class_getInstanceMethod(cls,selector),replacement);
 }
 if(STHSystemUIBlocked())forceHidden(view,state,YES);
}
static void scan(UIView *view,int depth,int *budget){
 if(!view||depth>10||--*budget<0)return;
 NSString *name=NSStringFromClass(view.class);
 if([name containsString:@"HostingView"]&&([name containsString:@"Stheno.Container"]||[name containsString:@"6Stheno9Container"]||[name isEqualToString:@"_UIHostingView<Container>"]))STHRegisterSthenoSurface(view);
 for(UIView *child in view.subviews)scan(child,depth+1,budget);
}
void STHRefreshSystemVisibility(void){
 if(!NSThread.isMainThread)return;
 CFTimeInterval now=CACurrentMediaTime();if(now<nextRefresh)return;nextRefresh=now+.15;
 unsigned known=0,observed=0;BOOL value=NO;
 if(readSource(@"SBControlCenterController",@[@"isVisible",@"isPresentedOrDismissing"],&value)){known|=1;if(value)observed|=1;}
 if(readSource(@"SBCoverSheetPresentationManager",@[@"isVisible",@"isPresented",@"isTransitioning"],&value)){known|=2;if(value)observed|=2;}
 if(readSource(@"SBLockScreenManager",@[@"isUILocked"],&value)){known|=4;if(value)observed|=4;}
 apply(STHVisibilitySample(&policy,known,observed,now));
 for(UIScene *s in UIApplication.sharedApplication.connectedScenes)if([s isKindOfClass:UIWindowScene.class])for(UIWindow *w in ((UIWindowScene *)s).windows){int budget=220;scan(w,0,&budget);}
}
static void hook(NSString *name,NSString *methodName,unsigned bit,BOOL value){
 Class cls=NSClassFromString(name);SEL sel=NSSelectorFromString(methodName);Method m=class_getInstanceMethod(cls,sel);char result[8]={0};
 if(!m||method_getNumberOfArguments(m)!=2)return;method_getReturnType(m,result,8);if(result[0]!='v')return;
 IMP original=method_getImplementation(m);
 method_setImplementation(m,imp_implementationWithBlock(^(id object){
  if(value)event(bit,YES);
  ((void(*)(id,SEL))original)(object,sel);
  if(!value)event(bit,NO);
 }));
}
void STHInstallSystemVisibility(void){
 static dispatch_once_t once;dispatch_once(&once,^{
  Class cls=NSClassFromString(@"SBLockScreenManager");SEL sel=NSSelectorFromString(@"_setUILocked:");Method m=class_getInstanceMethod(cls,sel);char argument[8]={0},result[8]={0};
  if(m){method_getArgumentType(m,2,argument,8);method_getReturnType(m,result,8);}
  if(m&&method_getNumberOfArguments(m)==3&&result[0]=='v'&&(argument[0]=='B'||argument[0]=='c')){
   IMP original=method_getImplementation(m);method_setImplementation(m,imp_implementationWithBlock(^(id object,BOOL value){if(value)event(4,YES);((void(*)(id,SEL,BOOL))original)(object,sel,value);if(!value)event(4,NO);}));
  }
  hook(@"SBControlCenterController",@"_willPresent",1,YES);hook(@"SBControlCenterController",@"_didDismiss",1,NO);
  hook(@"SBCoverSheetPresentationManager",@"_notifyDelegateWillPresent",2,YES);hook(@"SBCoverSheetPresentationManager",@"_notifyDelegateDidDismiss",2,NO);
  int token=-1;notify_register_dispatch("com.apple.springboard.lockstate",&token,dispatch_get_main_queue(),^(int n){(void)n;nextRefresh=0;STHRefreshSystemVisibility();});
  [NSNotificationCenter.defaultCenter addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){(void)note;nextRefresh=0;STHRefreshSystemVisibility();}];
  static dispatch_source_t timer;timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());dispatch_source_set_timer(timer,DISPATCH_TIME_NOW,NSEC_PER_SEC/5,NSEC_PER_SEC/30);dispatch_source_set_event_handler(timer,^{STHRefreshSystemVisibility();});dispatch_resume(timer);
 });
}
