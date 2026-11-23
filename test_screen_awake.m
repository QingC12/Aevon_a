#define STH_SCREEN_AWAKE_TEST 1
#import <Foundation/Foundation.h>
#import <assert.h>
#import "ScreenAwake.m"

static unsigned acquires,invalidates,resets;
static NSUInteger liveAssertions;
static BOOL coordinatorEnabled,assertionEnabled,getterDisabled,applicationEnabled;

// Models the real contract: the assertion stays in force while the object is
// alive and disappears on -invalidate. There is no release method.
@interface FakeAssertion:NSObject
@property BOOL valid;
@end
@implementation FakeAssertion
- (void)invalidate{
 if(!self.valid)return;
 self.valid=NO;if(liveAssertions)liveAssertions--;invalidates++;
}
@end
@interface SBIdleTimerGlobalCoordinator:NSObject
+ (instancetype)sharedInstance;
+ (instancetype)sharedInstanceIfExists;
+ (instancetype)_sharedInstanceCreateIfNeeded:(BOOL)flag;
- (id)acquireIdleTimerDisableAssertionForReason:(NSString *)value;
- (void)resetIdleTimerForReason:(NSString *)value;
- (BOOL)isIdleTimerDisabled;
@end
@implementation SBIdleTimerGlobalCoordinator
+ (instancetype)sharedInstance{return coordinatorEnabled?[self new]:nil;}
+ (instancetype)sharedInstanceIfExists{return coordinatorEnabled?[self new]:nil;}
+ (instancetype)_sharedInstanceCreateIfNeeded:(BOOL)flag{(void)flag;return coordinatorEnabled?[self new]:nil;}
- (id)acquireIdleTimerDisableAssertionForReason:(NSString *)value{
 assert([value isEqualToString:@"com.nx.stheno.floating-window"]);
 if(!assertionEnabled)return nil;
 acquires++;liveAssertions++;
 FakeAssertion *lease=[FakeAssertion new];lease.valid=YES;return lease;
}
- (void)resetIdleTimerForReason:(NSString *)value{
 assert([value isEqualToString:@"com.nx.stheno.floating-window"]);resets++;
}
- (BOOL)isIdleTimerDisabled{return getterDisabled?NO:liveAssertions>0;}
@end
@interface UIApplication:NSObject
@property(getter=isIdleTimerDisabled) BOOL idleTimerDisabled;
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

static void resetAll(void){
 STHScreenAwakeResetTestState();
 acquires=invalidates=resets=0;liveAssertions=0;
 coordinatorEnabled=YES;assertionEnabled=YES;getterDisabled=NO;applicationEnabled=YES;
}
int main(void){@autoreleasepool{
 // One live assertion per lease: acquired on the first visible card, held
 // across repeated ticks and card count changes, invalidated once at zero.
 resetAll();
 STHScreenAwakeUpdate(0);
 assert(!STHScreenAwakeHeld()&&acquires==0&&invalidates==0&&liveAssertions==0);
 STHScreenAwakeUpdate(1);
 assert(STHScreenAwakeHeld()&&acquires==1&&invalidates==0&&liveAssertions==1);
 STHScreenAwakeUpdate(3);
 STHScreenAwakeUpdate(2);
 assert(acquires==1&&invalidates==0&&liveAssertions==1);
 STHScreenAwakeUpdate(0);
 assert(!STHScreenAwakeHeld()&&invalidates==1&&liveAssertions==0);
 STHScreenAwakeUpdate(0);
 assert(invalidates==1);
 for(int i=0;i<200;i++){STHScreenAwakeUpdate(1);STHScreenAwakeUpdate(0);}
 assert(acquires==201&&invalidates==201&&liveAssertions==0);

 // A silently ignored assertion is rebuilt, then released exactly once.
 resetAll();
 STHScreenAwakeUpdate(1);
 assert(acquires==1&&liveAssertions==1);
 getterDisabled=YES;
 for(int i=0;i<4;i++)STHScreenAwakeUpdate(1);
 assert(acquires==1);
 STHScreenAwakeUpdate(1);
 assert(acquires==2&&invalidates==1&&liveAssertions==1);
 getterDisabled=NO;
 STHScreenAwakeUpdate(1);
 assert(acquires==2);
 STHScreenAwakeUpdate(0);
 assert(!STHScreenAwakeHeld()&&invalidates==2&&liveAssertions==0);

 // Rebuilding is capped: a backend that never honours the assertion degrades
 // to the reset heartbeat instead of stacking assertions forever.
 resetAll();
 getterDisabled=YES;
 STHScreenAwakeUpdate(1);
 for(int i=0;i<20;i++)STHScreenAwakeUpdate(1);
 assert(acquires==4&&resets>0&&liveAssertions==1);
 STHScreenAwakeUpdate(0);
 assert(!STHScreenAwakeHeld()&&liveAssertions==0);

 // An unsupported assertion API degrades to resetting the same countdown.
 resetAll();
 assertionEnabled=NO;
 STHScreenAwakeUpdate(1);
 assert(STHScreenAwakeHeld()&&acquires==0&&resets==1&&liveAssertions==0);
 STHScreenAwakeUpdate(1);STHScreenAwakeUpdate(1);
 assert(resets==3);
 STHScreenAwakeUpdate(0);STHScreenAwakeUpdate(0);
 assert(!STHScreenAwakeHeld()&&resets==3);

 // Application fallback: a normal idle timer is disabled and then restored.
 resetAll();
 coordinatorEnabled=NO;
 UIApplication *app=[UIApplication sharedApplication];
 app.idleTimerDisabled=NO;
 STHScreenAwakeUpdate(2);
 assert(STHScreenAwakeHeld()&&app.idleTimerDisabled);
 app.idleTimerDisabled=NO;
 STHScreenAwakeUpdate(2);
 assert(app.idleTimerDisabled);
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
 resetAll();
 STHScreenAwakeUpdate(1);STHScreenAwakeSuspend();STHScreenAwakeSuspend();
 assert(!STHScreenAwakeHeld()&&liveAssertions==0);
 resetAll();
 coordinatorEnabled=NO;applicationEnabled=NO;
 STHScreenAwakeUpdate(1);
 assert(!STHScreenAwakeHeld());
 STHScreenAwakeUpdate(0);
 assert(!STHScreenAwakeHeld());
 puts("ScreenAwake: assertion object is held once per lease and invalidated once; ignored assertions are rebuilt at most three times before the reset heartbeat; unsupported APIs degrade without stacking state; 200 cycles stay balanced");
}return 0;}
