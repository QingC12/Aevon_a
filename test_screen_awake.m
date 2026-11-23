#define STH_SCREEN_AWAKE_TEST 1
#import <Foundation/Foundation.h>
#import <assert.h>
#import "ScreenAwake.m"

static unsigned acquires,releases;
static BOOL coordinatorEnabled=YES,applicationEnabled=YES;
@interface SBIdleTimerGlobalCoordinator:NSObject @end
@implementation SBIdleTimerGlobalCoordinator
+ (instancetype)sharedInstance{return coordinatorEnabled?[self new]:nil;}
- (void)acquireIdleTimerDisableAssertionForReason:(NSString *)value{
 assert([value isEqualToString:@"com.nx.stheno.floating-window"]);acquires++;
}
- (void)releaseIdleTimerDisableAssertionForReason:(NSString *)value{
 assert([value isEqualToString:@"com.nx.stheno.floating-window"]);releases++;
}
@end
@interface UIApplication:NSObject
@property BOOL idleTimerDisabled;
+ (instancetype)sharedApplication;
@end
@implementation UIApplication
+ (instancetype)sharedApplication{
 static UIApplication *shared;
 if(!applicationEnabled)return nil;
 if(!shared)shared=[self new];
 return shared;
}
@end
int main(void){@autoreleasepool{
 // Coordinator path: one lease for any positive count, released at zero.
 STHScreenAwakeResetTestState();
 assert(!STHScreenAwakeHeld());
 STHScreenAwakeUpdate(0);
 assert(!STHScreenAwakeHeld()&&acquires==0&&releases==0);
 STHScreenAwakeUpdate(1);
 assert(STHScreenAwakeHeld()&&acquires==1&&releases==0);
 STHScreenAwakeUpdate(3);
 assert(acquires==1&&releases==0);
 STHScreenAwakeUpdate(0);
 assert(!STHScreenAwakeHeld()&&releases==1);
 STHScreenAwakeUpdate(0);
 assert(releases==1);
 for(int i=0;i<200;i++){STHScreenAwakeUpdate(1);STHScreenAwakeUpdate(0);}
 assert(acquires==201&&releases==201);

 // Application fallback: a normal idle timer is disabled and then restored.
 coordinatorEnabled=NO;STHScreenAwakeResetTestState();acquires=releases=0;
 UIApplication *app=[UIApplication sharedApplication];
 app.idleTimerDisabled=NO;
 STHScreenAwakeUpdate(2);
 NSLog(@"awake-debug held=%d idle=%d same=%d cls=%d shared=%d get=%d set=%d mode=%d",STHScreenAwakeHeld(),app.idleTimerDisabled,application==app,NSClassFromString(@"UIApplication")!=nil,[NSClassFromString(@"UIApplication") respondsToSelector:@selector(sharedApplication)],signature(app,@selector(isIdleTimerDisabled),'B',""),signature(app,@selector(setIdleTimerDisabled:),'v',"B"),applicationMode);
 assert(STHScreenAwakeHeld()&&app.idleTimerDisabled);
 STHScreenAwakeUpdate(0);
 assert(!STHScreenAwakeHeld()&&!app.idleTimerDisabled);

 // A pre-existing disabled idle timer survives the whole lease.
 app.idleTimerDisabled=YES;
 STHScreenAwakeUpdate(1);
 assert(STHScreenAwakeHeld()&&app.idleTimerDisabled);
 STHScreenAwakeUpdate(0);
 assert(app.idleTimerDisabled);

 // An external clear is never overridden on release.
 app.idleTimerDisabled=NO;
 STHScreenAwakeUpdate(1);
 app.idleTimerDisabled=NO;
 STHScreenAwakeUpdate(0);
 assert(!app.idleTimerDisabled);

 // Suspend is idempotent and works with no backend at all.
 STHScreenAwakeUpdate(1);STHScreenAwakeSuspend();STHScreenAwakeSuspend();
 assert(!STHScreenAwakeHeld());
 applicationEnabled=NO;STHScreenAwakeResetTestState();
 STHScreenAwakeUpdate(1);
 assert(!STHScreenAwakeHeld());
 STHScreenAwakeUpdate(0);
 puts("ScreenAwake: coordinator lease is idempotent and balanced across 200 cycles; application fallback restores NO and preserves YES; external clears and a missing backend stay safe");
}return 0;}
