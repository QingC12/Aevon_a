// Read-only diagnostics. Never requests notification contents/permissions,
// changes ringer/DND, synthesizes sounds, or edits saved preference flags.
#import <Foundation/Foundation.h>
#import "LayoutBus.h"
static id notificationPolicyObserver;
static NSNumber *lastMask;
static void recordNotificationPolicy(void){
 if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"])return;
 NSDictionary *domain=[NSUserDefaults.standardUserDefaults persistentDomainForName:@"com.nx.stheno"];
 id value=domain[@"SettingMask"];
 if(![value isKindOfClass:NSNumber.class]){
  STHWriteLayoutLog(@"notification-policy v2.0.13 saved foreground-notify state unavailable; no settings modified");return;
 }
 if([lastMask isEqual:value])return;lastMask=value;
 BOOL foreground=([value unsignedLongLongValue]&(1ULL<<27))!=0;
 STHWriteLayoutLog([NSString stringWithFormat:@"notification-policy v2.0.13 foreground-notify-option=%d action=diagnostic-only; normal system sound/silent/focus decisions preserved",foreground]);
}
__attribute__((constructor)) static void notificationPolicyReady(void){
 dispatch_async(dispatch_get_main_queue(),^{
  recordNotificationPolicy();
  notificationPolicyObserver=[NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){recordNotificationPolicy();}];
 });
}
