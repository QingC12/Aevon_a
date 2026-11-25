#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <assert.h>
#include <stdlib.h>
#include <stdint.h>
extern NSArray *STHChooserSnapshotUnpinned(void);
extern BOOL STHChooserSubmitFloating(NSString *);
extern BOOL STHChooserSubmitCenterSelection(void);
typedef struct{uintptr_t name[2],identifier[2];} App;
uintptr_t sth_action_core_base;static BOOL ready=YES,enabled=YES;
static BOOL disableInCatalog,disableInBuilder,failBuilder;
static unsigned catalogCopies,builds;
BOOL STHSystemActionsEnabled(void){return enabled;}
static NSArray *user,*systemRows;static NSMutableArray *pinned;static NSMutableSet *buffers;
static unsigned arrays,models,opens;static NSString *lastOpened;
BOOL STHSystemActionRuntimeReady(void){return ready;}
void STHSystemMakeSwiftString(NSString *s,uintptr_t words[2]){words[0]=(uintptr_t)CFBridgingRetain(s);words[1]=0x1234;}
void *STHSystemCopySwiftString(const uintptr_t words[2]){assert(words[1]==0x1234);return (void *)CFRetain((CFTypeRef)words[0]);}
void *STHSystemCopyModelIdentifier(void *model){return (void *)CFRetain(model);}
static void *copyApps(NSArray *rows){
 uintptr_t *raw=calloc(1,32+rows.count*32);raw[2]=rows.count;raw[3]=rows.count*2;
 App *apps=(void *)((char *)raw+32);
 for(NSUInteger i=0;i<rows.count;i++){STHSystemMakeSwiftString(rows[i][@"name"],apps[i].name);STHSystemMakeSwiftString(rows[i][@"identifier"],apps[i].identifier);}
 [buffers addObject:[NSValue valueWithPointer:raw]];arrays++;return raw;
}
int STHChooserCopyCatalogs(void **out){catalogCopies++;out[0]=copyApps(user);out[1]=copyApps(systemRows);if(disableInCatalog)enabled=NO;return YES;}
void *STHChooserCopyPinnedManagers(void){arrays++;return (void *)CFBridgingRetain([pinned copy]);}
size_t STHChooserManagersCount(void *raw){return [(__bridge NSArray *)raw count];}
void *STHChooserCopyManagerAt(size_t index,void *raw){models++;return (void *)CFBridgingRetain(((__bridge NSArray *)raw)[index]);}
void STHChooserReleaseSwift(void *model){assert(models);models--;CFRelease(model);}
void STHChooserReleaseArray(void *raw){
 NSValue *key=[NSValue valueWithPointer:raw];
 if([buffers containsObject:key]){
  App *apps=(void *)((char *)raw+32);size_t count=((uintptr_t *)raw)[2];
  for(size_t i=0;i<count;i++){CFRelease((CFTypeRef)apps[i].name[0]);CFRelease((CFTypeRef)apps[i].identifier[0]);}
  [buffers removeObject:key];free(raw);
 }else CFRelease(raw);
 assert(arrays);arrays--;
}
void *STHChooserBuildManagerConsumed(uintptr_t first,uintptr_t second){assert(second==0x1234);builds++;if(disableInBuilder)enabled=NO;if(failBuilder){CFRelease((CFTypeRef)first);return NULL;}models++;return (void *)first;}
void STHChooserOpenModelAnimated(void *model){opens++;lastOpened=[(__bridge NSString *)model copy];}
static NSDictionary *row(NSString *id,NSString *name){return @{@"identifier":id,@"name":name};}
#if defined(STH_CHOOSER_SEARCH_TEST)
void STHTestPrepareSearchCatalog(BOOL pinFree){
 assert(!arrays&&!models);ready=YES;enabled=YES;disableInCatalog=disableInBuilder=failBuilder=NO;
 if(!buffers)buffers=[NSMutableSet set];
 pinned=[NSMutableArray arrayWithObject:@"pinned.app"];
 if(pinFree)[pinned addObject:@"com.tencent.xin"];
 user=@[row(@"pinned.app",@"已添加"),row(@"com.tencent.xin",@"微信"),row(@"com.openminis.app",@"Minis"),row(@"com.nx.stheno.action.screenshot",@"截图")];
 systemRows=@[row(@"com.openminis.app",@"重复"),row(@"com.apple.Preferences",@"设置")];
}
void STHTestAssertSearchReleased(void){assert(!arrays&&!models);}
#else
int main(void){@autoreleasepool{
 buffers=[NSMutableSet set];pinned=[NSMutableArray arrayWithObject:@"pinned.app"];
 user=@[row(@"pinned.app",@"已添加"),row(@"free.app",@"未添加"),row(@"duplicate.app",@"重复"),row(@"com.nx.stheno.action.screenshot",@"截图")];
 systemRows=@[row(@"duplicate.app",@"重复"),row(@"system.free",@"系统应用"),row(@"com.nx.stheno.action.screen-recording",@"录屏")];
 NSArray *before=[pinned copy],*rows=STHChooserSnapshotUnpinned();
 assert(rows.count==3&&[rows[0][@"identifier"] isEqualToString:@"free.app"]);
 assert([rows[2][@"source"] isEqualToString:@"system"]);assert(arrays==0&&models==0);
 for(int i=0;i<100;i++){assert(STHChooserSnapshotUnpinned().count==3);assert(!arrays&&!models);}
 assert(STHChooserSubmitFloating(@"free.app"));assert(opens==1&&[lastOpened isEqualToString:@"free.app"]);assert(!arrays&&!models);assert([pinned isEqualToArray:before]);
 assert(!STHChooserSubmitFloating(@"pinned.app"));assert(!STHChooserSubmitFloating(@"absent.app"));
 assert(!STHChooserSubmitFloating(@"com.nx.stheno.action.screenshot"));assert(opens==1);
 [pinned addObject:@"free.app"];assert(!STHChooserSubmitFloating(@"free.app"));assert(opens==1&&!arrays&&!models);
 assert(STHChooserSubmitCenterSelection());assert(opens==2&&[lastOpened isEqualToString:@"com.nx.stheno.action.app-picker"]);assert(!arrays&&!models);
 assert(pinned.count==before.count+1);
 unsigned copiesBefore=catalogCopies,buildsBefore=builds;
 enabled=NO;
 assert(!STHChooserSubmitFloating(@"system.free"));assert(!STHChooserSubmitCenterSelection());
 assert(opens==2&&catalogCopies==copiesBefore&&builds==buildsBefore&&!arrays&&!models);
 enabled=YES;disableInCatalog=YES;
 assert(!STHChooserSubmitFloating(@"system.free"));
 assert(opens==2&&builds==buildsBefore&&!arrays&&!models);
 disableInCatalog=NO;disableInBuilder=YES;enabled=YES;
 assert(!STHChooserSubmitFloating(@"system.free"));assert(opens==2&&!arrays&&!models);
 enabled=YES;assert(!STHChooserSubmitCenterSelection());assert(opens==2&&!arrays&&!models);
 disableInBuilder=NO;enabled=YES;
 assert(STHChooserSubmitFloating(@"system.free"));assert(opens==3&&!arrays&&!models);
 assert(STHChooserSubmitCenterSelection());assert(opens==4&&!arrays&&!models);
 failBuilder=YES;assert(!STHChooserSubmitFloating(@"system.free"));assert(!STHChooserSubmitCenterSelection());
 assert(opens==4&&!arrays&&!models);failBuilder=NO;
 copiesBefore=catalogCopies;buildsBefore=builds;
 assert(!STHChooserSubmitFloating(nil));assert(!STHChooserSubmitFloating(@""));
 __block BOOL offMainFloating=YES,offMainCenter=YES;
 dispatch_semaphore_t done=dispatch_semaphore_create(0);
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{
  offMainFloating=STHChooserSubmitFloating(@"system.free");
  offMainCenter=STHChooserSubmitCenterSelection();dispatch_semaphore_signal(done);
 });
 dispatch_semaphore_wait(done,DISPATCH_TIME_FOREVER);
 assert(!offMainFloating&&!offMainCenter&&copiesBefore==catalogCopies&&buildsBefore==builds&&opens==4&&!arrays&&!models);
 ready=NO;assert(!STHChooserSnapshotUnpinned());assert(!STHChooserSubmitFloating(@"system.free"));assert(!STHChooserSubmitCenterSelection());
 NSLog(@"Chooser catalog passed: unpinned-only, dedup, action exclusion, stale membership recheck, native animated submission, no pin writes, 100 ownership cycles");
}return 0;}
#endif
