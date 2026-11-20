#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <stdatomic.h>
#import "SystemVisibilityBridge.h"
NSNotificationName const SthenoSystemVisibilityChanged=@"SthenoSystemVisibilityChanged";
static atomic_bool blocked;
static unsigned sources,latched;
static NSMapTable<UIView *,NSNumber *> *hidden;
static NSMutableSet *hooked;
static BOOL applying;
static char registered;
BOOL STHSystemUIBlocked(void){return atomic_load(&blocked);}
static BOOL readFlag(NSString *name,NSString *flag){
 Class cls=NSClassFromString(name);SEL shared=NSSelectorFromString(@"sharedInstanceIfExists");
 if(![cls respondsToSelector:shared])return NO;
 id object=((id(*)(id,SEL))objc_msgSend)(cls,shared);SEL sel=NSSelectorFromString(flag);
 NSMethodSignature *s=[object methodSignatureForSelector:sel];
 if(!s||s.numberOfArguments!=2||(s.methodReturnType[0]!='B'&&s.methodReturnType[0]!='c'))return NO;
 return ((BOOL(*)(id,SEL))objc_msgSend)(object,sel);
}
static void apply(BOOL value){
 BOOL previous=atomic_exchange(&blocked,value);if(previous==value)return;
 applying=YES;
 for(UIView *view in hidden.keyEnumerator.allObjects){
  if(value){[hidden setObject:@(view.hidden) forKey:view];view.hidden=YES;}
  else view.hidden=[[hidden objectForKey:view] boolValue];
 }
 applying=NO;
 [NSNotificationCenter.defaultCenter postNotificationName:SthenoSystemVisibilityChanged object:nil];
}
static void change(unsigned source,BOOL value){
 if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{change(source,value);});return;}
 if(value){sources|=source;latched|=source;}else{sources&=~source;latched&=~source;}
 apply(sources!=0);
}
void STHRegisterSthenoSurface(UIView *view){
 if(!view||objc_getAssociatedObject(view,&registered))return;
 if(!hidden)hidden=[NSMapTable weakToStrongObjectsMapTable];
 objc_setAssociatedObject(view,&registered,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 [hidden setObject:@(view.hidden) forKey:view];
 Class cls=view.class;NSString *name=NSStringFromClass(cls);
 if(!hooked)hooked=[NSMutableSet set];
 if(![hooked containsObject:name]){
  [hooked addObject:name];SEL selector=@selector(setHidden:);Method method=class_getInstanceMethod(cls,selector);IMP original=method_getImplementation(method);
  IMP replacement=imp_implementationWithBlock(^(UIView *target,BOOL value){
   if(objc_getAssociatedObject(target,&registered)&&!applying){[hidden setObject:@(value) forKey:target];if(STHSystemUIBlocked())value=YES;}
   ((void(*)(id,SEL,BOOL))original)(target,selector,value);
  });
  if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method)))method_setImplementation(class_getInstanceMethod(cls,selector),replacement);
 }
 if(STHSystemUIBlocked()){applying=YES;view.hidden=YES;applying=NO;}
}
static void scan(UIView *view,int depth,int *budget){
 if(!view||depth>10||--*budget<0)return;
 NSString *name=NSStringFromClass(view.class);
 if([name containsString:@"HostingView"]&&([name containsString:@"Stheno.Container"]||[name containsString:@"6Stheno9Container"]||[name isEqualToString:@"_UIHostingView<Container>"]))STHRegisterSthenoSurface(view);
 for(UIView *child in view.subviews)scan(child,depth+1,budget);
}
void STHRefreshSystemVisibility(void){
 if(!NSThread.isMainThread)return;
 static CFTimeInterval next=0;CFTimeInterval now=CACurrentMediaTime();if(now<next)return;next=now+.15;
 unsigned value=0;
 if(readFlag(@"SBControlCenterController",@"isVisible")||readFlag(@"SBControlCenterController",@"isPresentedOrDismissing"))value|=1;
 if(readFlag(@"SBCoverSheetPresentationManager",@"isVisible"))value|=2;
 if(readFlag(@"SBLockScreenManager",@"isUILocked"))value|=4;
 sources=value|latched;apply(sources!=0);
 for(UIScene *s in UIApplication.sharedApplication.connectedScenes)if([s isKindOfClass:UIWindowScene.class])for(UIWindow *w in ((UIWindowScene *)s).windows){int budget=220;scan(w,0,&budget);}
}
static void hook(NSString *name,NSString *methodName,unsigned source,BOOL value){
 Class cls=NSClassFromString(name);SEL sel=NSSelectorFromString(methodName);Method m=class_getInstanceMethod(cls,sel);
 char type[8]={0};if(!m||method_getNumberOfArguments(m)!=2)return;method_getReturnType(m,type,8);if(type[0]!='v')return;
 IMP original=method_getImplementation(m);
 method_setImplementation(m,imp_implementationWithBlock(^(id object){
  if(value)change(source,YES);
  ((void(*)(id,SEL))original)(object,sel);
  if(!value){change(source,NO);STHRefreshSystemVisibility();}
 }));
}
void STHInstallSystemVisibility(void){
 static dispatch_once_t once;dispatch_once(&once,^{
  Class lockClass=NSClassFromString(@"SBLockScreenManager");SEL lockSelector=NSSelectorFromString(@"_setUILocked:");
  Method lockMethod=class_getInstanceMethod(lockClass,lockSelector);char argument[8]={0},result[8]={0};
  if(lockMethod){method_getArgumentType(lockMethod,2,argument,8);method_getReturnType(lockMethod,result,8);}
  if(lockMethod&&method_getNumberOfArguments(lockMethod)==3&&result[0]=='v'&&(argument[0]=='B'||argument[0]=='c')){
   IMP original=method_getImplementation(lockMethod);
   method_setImplementation(lockMethod,imp_implementationWithBlock(^(id object,BOOL value){if(value)change(4,YES);((void(*)(id,SEL,BOOL))original)(object,lockSelector,value);if(!value)change(4,NO);}));
  }
  hook(@"SBControlCenterController",@"_willPresent",1,YES);hook(@"SBControlCenterController",@"_didDismiss",1,NO);
  hook(@"SBCoverSheetPresentationManager",@"_notifyDelegateWillPresent",2,YES);hook(@"SBCoverSheetPresentationManager",@"_notifyDelegateDidDismiss",2,NO);
  int token=-1;notify_register_dispatch("com.apple.springboard.lockstate",&token,dispatch_get_main_queue(),^(int n){(void)n;STHRefreshSystemVisibility();});
  [NSNotificationCenter.defaultCenter addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){(void)note;STHRefreshSystemVisibility();}];
  dispatch_async(dispatch_get_main_queue(),^{STHRefreshSystemVisibility();});
 });
}
