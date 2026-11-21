#import "ViewportStartup.h"
#import "ViewportProcess.h"
@interface STHVStartupGate:NSObject
@property BOOL queued,finished;
@property(copy) dispatch_block_t install;
@property(strong) NSBundle *bundle;
@property(strong) NSNotificationCenter *center;
@property(strong) NSMutableArray *tokens;
@end
@implementation STHVStartupGate
-(void)observe:(NSNotification *)note{
 @synchronized(self){if(self.queued||self.finished)return;self.queued=YES;}
 dispatch_async(dispatch_get_main_queue(),^{
  if(self.finished)return;self.finished=YES;
  for(id token in self.tokens)[self.center removeObserver:token];
  [self.tokens removeAllObjects];
  dispatch_block_t install=self.install;self.install=nil;
  if(STHVApplicationBundleAllowed(self.bundle)&&install)install();
 });
}
@end
void STHVObserveApplicationLaunch(NSBundle *bundle,NSNotificationCenter *center,NSArray<NSString *> *events,dispatch_block_t install){
 if(!STHVApplicationBundleAllowed(bundle)||!center||!events.count||!install)return;
 STHVStartupGate *gate=[STHVStartupGate new];gate.bundle=bundle;gate.center=center;
 gate.install=install;gate.tokens=[NSMutableArray new];
 for(NSString *event in events){id token=[center addObserverForName:event object:nil queue:nil usingBlock:^(NSNotification *note){[gate observe:note];}];[gate.tokens addObject:token];}
}
