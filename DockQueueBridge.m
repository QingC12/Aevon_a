#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "DockOrientation.h"
#include <stdbool.h>
#import <dlfcn.h>
extern void *STHDockCopyFloating(void);
extern size_t STHChooserManagersCount(void *);
extern void *STHChooserCopyManagerAt(size_t,void *);
extern void STHChooserReleaseArray(void *),STHChooserReleaseSwift(void *);
extern BOOL STHDockNativeMinimized(void *);
extern NSUInteger STHDockNativeOrientation(void *);
extern CGSize STHDockNativeOffset(void *);
extern void STHDockNativeSetOffset(void *,double,double);
extern CGRect STHDockNativeRect(void *);
extern void STHDockSwiftReflow(void);
extern void STHDockNativeAnimate(void);
static NSMutableArray<NSValue *> *models;
static BOOL reflowing;
static double originY,top,bottom;
static unsigned blockedSides;
static NSArray *lastMembers;
static UIWindow *hostWindow(void){
 for(UIScene *s in UIApplication.sharedApplication.connectedScenes)if([s isKindOfClass:UIWindowScene.class])
  for(UIWindow *w in ((UIWindowScene *)s).windows)if([NSStringFromClass(w.class) containsString:@"SthenoWindow"])return w;
 return nil;
}
int64_t STHDockCount(void){return models.count;}
BOOL STHDockRead(int64_t index,uintptr_t *key,int32_t *side,double *height){
 if(index<0||index>=(int64_t)models.count)return NO;
 void *m=models[index].pointerValue;CGSize offset=STHDockNativeOffset(m);CGRect frame=STHDockNativeRect(m);
 if(!isfinite(offset.width)||!isfinite(frame.size.height)||frame.size.height<1)return NO;
 *key=(uintptr_t)m;*side=offset.width<0?0:1;*height=frame.size.height;return YES;
}
void STHDockApply(uintptr_t key,double centerY){
 void *m=(void *)key;CGSize p=STHDockNativeOffset(m);
 if(!STHDockMayApply(blockedSides,p.width,(unsigned)STHDockNativeOrientation(m)))return;
 double y=centerY-originY;
 if(fabs(y-p.height)>.25)STHDockNativeSetOffset(m,p.width,y);
}
double STHDockTop(void){return top;}
double STHDockBottom(void){return bottom;}
void STHDockReflow(void){
 if(reflowing||!NSThread.isMainThread)return;reflowing=YES;
 void *array=STHDockCopyFloating();
 if(!array){reflowing=NO;return;}
 models=[NSMutableArray array];
 static void (*keyboardMinimized)(void *);
 if(!keyboardMinimized)keyboardMinimized=dlsym(RTLD_DEFAULT,"STHViewportModelMinimized");
 blockedSides=0;
 @try{
  size_t n=STHChooserManagersCount(array);if(n>4096)return;
  for(size_t i=0;i<n;i++){
   void *m=STHChooserCopyManagerAt(i,array);
   if(STHDockNativeMinimized(m)){
    if(keyboardMinimized)keyboardMinimized(m);
    CGSize offset=STHDockNativeOffset(m);
    if(!STHDockUsesNativeReflow((unsigned)STHDockNativeOrientation(m)))blockedSides|=offset.width<0?1u:2u;
    [models addObject:[NSValue valueWithPointer:m]];
   }else STHChooserReleaseSwift(m);
  }
  UIScreen *s=UIScreen.mainScreen;CGFloat h=MAX(s.bounds.size.width,s.bounds.size.height);UIEdgeInsets safe=hostWindow().safeAreaInsets;
  originY=h/2;top=MAX(28,safe.top)+8;bottom=h-MAX(20,safe.bottom)-8;
  if(models.count)STHDockSwiftReflow();
  lastMembers=[models copy];
 }@finally{
  for(NSValue *v in models)STHChooserReleaseSwift(v.pointerValue);
  models=nil;STHChooserReleaseArray(array);reflowing=NO;
 }
}
void STHInstallDockQueue(void){
 // State-changing callbacks reflow inside their caller's existing animation.
 // This watchdog only catches models removed through another native route.
 static dispatch_source_t timer;
 if(timer)return;
 timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
 dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC/3,NSEC_PER_SEC/20);
 dispatch_source_set_event_handler(timer,^{
  if(!lastMembers.count)return;
  void *a=STHDockCopyFloating();if(!a)return;
  NSMutableArray *current=[NSMutableArray array];size_t n=STHChooserManagersCount(a);
  if(n<=4096)for(size_t i=0;i<n;i++){void *m=STHChooserCopyManagerAt(i,a);if(STHDockNativeMinimized(m))[current addObject:[NSValue valueWithPointer:m]];STHChooserReleaseSwift(m);}
  STHChooserReleaseArray(a);
  if(![current isEqualToArray:lastMembers])STHDockNativeAnimate();
 });dispatch_resume(timer);
}
