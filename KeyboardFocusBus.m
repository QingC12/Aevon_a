#import "KeyboardFocusBus.h"
#import <notify.h>
#include <stdint.h>
static NSString *const changed=@"com.nx.stheno.input-owner.v2";
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
#include "KeyboardFocusFrame.inc"
void STHPublishInputFocus(NSString *bundle,BOOL active){publishSnapshot(bundle,active,NO,(STHRect){0,0,0,0});}
BOOL STHReadInputFocus(NSString *bundle){return readSnapshot(bundle,NO,NULL);}
void STHObserveInputFocus(dispatch_block_t block){
 static int observation=-1;if(observation>=0||!block)return;
 notify_register_dispatch(changed.UTF8String,&observation,dispatch_get_main_queue(),^(int unused){block();});
}
