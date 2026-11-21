#import <Foundation/Foundation.h>
#import <assert.h>
#import <stdio.h>
#import "ViewportStartup.h"
#import "ViewportProcess.h"
@interface LaunchBundle:NSBundle
@property(copy) NSString *pathValue,*idValue;
@property(strong) NSDictionary *metadata;
@end
@implementation LaunchBundle
-(NSString *)bundlePath{return self.pathValue;}
-(NSString *)bundleIdentifier{return self.idValue;}
-(NSDictionary *)infoDictionary{return self.metadata;}
@end
static LaunchBundle *bundleFor(NSString *path,NSString *package,id extension){LaunchBundle *b=[LaunchBundle new];b.pathValue=path;b.idValue=@"test.stheno.main";NSMutableDictionary *d=[@{@"CFBundlePackageType":package} mutableCopy];if(extension)d[@"NSExtension"]=extension;b.metadata=d;return b;}
static void drainUntil(BOOL (^done)(void)){
 for(int i=0;i<100&&!done();i++)[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
 assert(done());
}
int main(void){@autoreleasepool{
 NSArray *excluded=@[
  bundleFor(@"/Applications/App.app/PlugIns/Widget.appex",@"XPC!",@{}),
  bundleFor(@"/Applications/Fake.app",@"APPL",@{}),
  bundleFor(@"/System/Library/Service.xpc/Wrapper.app",@"APPL",nil),
  bundleFor(@"/usr/libexec/chronod",@"APPL",nil),
  bundleFor(@"/Applications/Unknown.app",@"BNDL",nil)];
 __block int blockedInstalls=0;
 for(LaunchBundle *b in excluded){
  assert(!STHVApplicationBundleAllowed(b));
  NSNotificationCenter *center=[NSNotificationCenter new];
  STHVObserveApplicationLaunch(b,center,@[@"launch",@"active"],^{blockedInstalls++;});
  [center postNotificationName:@"launch" object:nil];[center postNotificationName:@"active" object:nil];
 }
 LaunchBundle *shell=bundleFor(@"/System/Library/CoreServices/SpringBoard.app",@"APPL",nil);shell.idValue=@"com.apple.springboard";assert(!STHVApplicationBundleAllowed(shell));
 for(int cycle=0;cycle<200;cycle++){
  NSNotificationCenter *center=[NSNotificationCenter new];LaunchBundle *b=bundleFor(@"/Applications/Normal.app",@"APPL",nil);
  __block int installs=0;__block BOOL delivering=NO;
  STHVObserveApplicationLaunch(b,center,@[@"launch",@"active"],^{assert(NSThread.isMainThread&&!delivering);installs++;});
  assert(!installs);delivering=YES;
  for(int i=0;i<20;i++){[center postNotificationName:@"launch" object:nil];[center postNotificationName:@"active" object:nil];}
  assert(!installs);delivering=NO;drainUntil(^BOOL{return installs==1;});
  [center postNotificationName:@"active" object:nil];assert(installs==1);
 }
 assert(blockedInstalls==0);
 puts("Viewport33 startup: 200 observed-launch/coalescing/deferred-install cycles; no install before launch or inside notification; Widget/appex/XPC/service/SpringBoard are inert");
}return 0;}
