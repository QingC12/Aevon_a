#import "KeyboardFocusBus.h"
#import <notify.h>
#include <stdint.h>
static NSString *const changed=@"com.nx.stheno.input-owner.v1";
static uint64_t bundleKey(NSString *s){
 uint64_t h=14695981039346656037ull;
 for(const unsigned char *p=(const unsigned char *)s.UTF8String;p&&*p;p++){h^=*p;h*=1099511628211ull;}
 return h?:1;
}
static int token(NSString *name){
 static NSMutableDictionary *tokens;
 if(!tokens)tokens=[NSMutableDictionary new];
 NSNumber *n=tokens[name];if(n)return n.intValue;
 int value=-1;if(notify_register_check(name.UTF8String,&value)!=NOTIFY_STATUS_OK)return -1;
 tokens[name]=@(value);return value;
}
static NSString *leaseName(NSString *s){return [changed stringByAppendingFormat:@".%@",s];}
void STHPublishInputFocus(NSString *bundle,BOOL active){
 if(!NSThread.isMainThread||!bundle.length)return;
 int global=token(changed),lease=token(leaseName(bundle));if(global<0||lease<0)return;
 uint64_t current=0;notify_get_state(global,&current);
 if(active){
  uint64_t stamp=(uint64_t)(NSProcessInfo.processInfo.systemUptime*1000.0)+1;
  notify_set_state(lease,stamp);notify_set_state(global,bundleKey(bundle));
 }else{
  notify_set_state(lease,0);
  if(current!=bundleKey(bundle))return;
  notify_set_state(global,0);
 }
 notify_post(changed.UTF8String);
}
BOOL STHReadInputFocus(NSString *bundle){
 if(!NSThread.isMainThread||!bundle.length)return NO;
 int global=token(changed),lease=token(leaseName(bundle));uint64_t key=0,stamp=0,after=0;
 if(global<0||lease<0||notify_get_state(global,&key)||key!=bundleKey(bundle)||notify_get_state(lease,&stamp)||!stamp||notify_get_state(global,&after)||after!=key)return NO;
 double age=NSProcessInfo.processInfo.systemUptime-((double)(stamp-1)/1000.0);
 return age>=-.05&&age<3;
}
void STHObserveInputFocus(dispatch_block_t block){
 static int observation=-1;if(observation>=0||!block)return;
 notify_register_dispatch(changed.UTF8String,&observation,dispatch_get_main_queue(),^(int unused){block();});
}
