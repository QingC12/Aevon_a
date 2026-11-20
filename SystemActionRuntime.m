#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <objc/runtime.h>
#import "SystemActionCatalog.h"

uintptr_t sth_action_core_base;
BOOL STHSystemActionRuntimeReady(void){
 if(sth_action_core_base)return YES;
 for(uint32_t i=0;i<_dyld_image_count();i++){
  const char *name=_dyld_get_image_name(i);if(!name)continue;
  if(![[[NSString stringWithUTF8String:name] lastPathComponent] isEqualToString:@"Stheno.dylib"])continue;
  const struct mach_header_64 *header=(const struct mach_header_64 *)_dyld_get_image_header(i);
  if(header->magic!=MH_MAGIC_64||header->cputype!=CPU_TYPE_ARM64||(header->cpusubtype&0xffffff)!=2)return NO;
  sth_action_core_base=(uintptr_t)header;return YES;
 }
 return NO;
}
BOOL STHSystemActionsEnabled(void){
 id value=[NSUserDefaults.standardUserDefaults persistentDomainForName:@"com.nx.stheno"][@"Inject"];
 return ![value isKindOfClass:NSNumber.class]||[value boolValue];
}
