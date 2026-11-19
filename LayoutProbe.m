#import "LayoutProbe.h"
#import "LayoutBus.h"
#import <notify.h>
#include <string.h>
@interface STHProbeTokens:NSObject
@property(nonatomic,strong) NSArray<NSNumber *> *names;
@property int frame;
@property int commit;
@property BOOL observed;
@property BOOL valid;
@end
@implementation STHProbeTokens @end
static NSMutableDictionary *probes;
static NSString *name(NSString *bundle,NSString *field){return[NSString stringWithFormat:@"com.nx.stheno.probe.v1.%@.%@",bundle,field];}
static int reg(NSString *bundle,NSString *field){int t=-1;notify_register_check(name(bundle,field).UTF8String,&t);return t;}
static STHProbeTokens *get(NSString *b){
 if(!b.length||b.length>160||[b rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"] invertedSet]].location!=NSNotFound)return nil;
 if(!probes)probes=[NSMutableDictionary new];STHProbeTokens *p=probes[b];if(p)return p;
 p=[STHProbeTokens new];NSMutableArray *n=[NSMutableArray new];
 p.valid=YES;for(int i=0;i<8;i++){int t=reg(b,[@"name" stringByAppendingFormat:@"%d",i]);[n addObject:@(t)];p.valid&=t>=0;}
 p.names=n;p.frame=reg(b,@"frame");p.commit=reg(b,@"commit");p.valid&=p.frame>=0&&p.commit>=0;
 probes[b]=p;return p;
}
void STHObserveLayoutProbe(NSString *b){
 STHProbeTokens *p=get(b);if(!p.valid||p.observed)return;p.observed=YES;
 int observer=-1;notify_register_dispatch(name(b,@"changed").UTF8String,&observer,dispatch_get_main_queue(),^(int t){
  uint64_t first=0,last=0,r=0,v=0;char chars[65]={0};
  notify_get_state(p.commit,&first);if(!(first>>63))return;
  notify_get_state(p.frame,&r);
  for(int i=0;i<8;i++){notify_get_state(p.names[i].intValue,&v);memcpy(chars+i*8,&v,8);}
  notify_get_state(p.commit,&last);if(first!=last)return;
  NSString *className=[NSString stringWithUTF8String:chars];if(!className)return;
  STHRect f=STHUnpackRect(r);
  STHWriteLayoutLog([NSString stringWithFormat:@"view-probe bundle=%@ class=%@ frame={%.3f,%.3f,%.3f,%.3f} flags=%u (class/geometry only)",b,className,f.x,f.y,f.w,f.h,(unsigned)(last&0xffff)]);
 });
}
void STHReportLayoutProbe(NSString *b,NSString *className,CGRect f,unsigned flags){
 STHProbeTokens *p=get(b);if(!p.valid||!className.length)return;
 uint64_t rect=0;if(!STHPackRect((STHRect){f.origin.x,f.origin.y,f.size.width,f.size.height},&rect))return;
 char chars[64]={0};NSData *d=[className dataUsingEncoding:NSUTF8StringEncoding];memcpy(chars,d.bytes,MIN(d.length,63));
 static uint64_t sequence;
 notify_set_state(p.commit,0);
 for(int i=0;i<8;i++){uint64_t v=0;memcpy(&v,chars+i*8,8);notify_set_state(p.names[i].intValue,v);}
 notify_set_state(p.frame,rect);notify_set_state(p.commit,(1ULL<<63)|((++sequence&0x7fffffffULL)<<16)|(flags&0xffff));
 notify_post(name(b,@"changed").UTF8String);
}
