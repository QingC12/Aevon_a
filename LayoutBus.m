#import "LayoutBus.h"
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <syslog.h>

@interface STHLayoutTokens : NSObject
@property int card;
@property int keyboard;
@property int commit;
@property int ack;
@property int observed;
@property BOOL valid;
@property BOOL ackObserved;
@end
@implementation STHLayoutTokens
@end
static NSMutableDictionary<NSString *,STHLayoutTokens *> *tokens;
static NSString *channel(NSString *bundle,NSString *field) {
 return [NSString stringWithFormat:@"com.nx.stheno.layout.v3.%@.%@",bundle,field];
}
static STHLayoutTokens *getTokens(NSString *bundle) {
 if(![bundle isKindOfClass:NSString.class]||bundle.length==0||bundle.length>160)return nil;
 NSCharacterSet *invalid=[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"] invertedSet];
 if([bundle rangeOfCharacterFromSet:invalid].location!=NSNotFound)return nil;
 if(!tokens)tokens=[NSMutableDictionary new];
 STHLayoutTokens *t=tokens[bundle];if(t)return t;
 t=[STHLayoutTokens new];t.card=t.keyboard=t.commit=t.ack=t.observed=-1;
 int card=-1,keyboard=-1,commit=-1,ack=-1;
 uint32_t a=notify_register_check(channel(bundle,@"card").UTF8String,&card);
 uint32_t b=notify_register_check(channel(bundle,@"keyboard").UTF8String,&keyboard);
 uint32_t c=notify_register_check(channel(bundle,@"commit").UTF8String,&commit);
 uint32_t d=notify_register_check(channel(bundle,@"ack").UTF8String,&ack);
 t.card=card;t.keyboard=keyboard;t.commit=commit;t.ack=ack;
 t.valid=a==0&&b==0&&c==0&&d==0;
 tokens[bundle]=t;return t;
}
void STHWriteLayoutLog(NSString *line) {
 if(![line isKindOfClass:NSString.class])return;
 NSString *text=[NSString stringWithFormat:@"%.3f %@ %@\n",CACurrentMediaTime(),NSBundle.mainBundle.bundleIdentifier,line];
 NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];
 // SpringBoard can write its own home; sandboxed apps fall back to THEIR home.
 NSArray *paths=@[@"/var/mobile/Documents/SthenoKeyboardLayout.log",
  [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/SthenoKeyboardLayout.log"],
  [NSTemporaryDirectory() stringByAppendingPathComponent:@"SthenoKeyboardLayout.log"]];
 for(NSString *path in paths){
  @try{
   NSFileManager *fm=NSFileManager.defaultManager;
   NSDictionary *attr=[fm attributesOfItemAtPath:path error:NULL];
   if([attr[NSFileSize] unsignedLongLongValue]>262144)[fm removeItemAtPath:path error:NULL];
   if(![fm fileExistsAtPath:path]&&![fm createFileAtPath:path contents:nil attributes:@{NSFilePosixPermissions:@0600}])continue;
   NSFileHandle *f=[NSFileHandle fileHandleForWritingAtPath:path];if(!f)continue;
   [f seekToEndOfFile];[f writeData:data];[f closeFile];return;
  }@catch(NSException *e){}
 }
 syslog(LOG_NOTICE,"Stheno keyboard layout: %s",line.UTF8String);
}
static uint64_t nowMilliseconds(void) { return (uint64_t)(CACurrentMediaTime()*1000.0); }

BOOL STHPublishLayout(NSString *bundle,CGRect card,CGRect keyboard,BOOL active) {
 STHLayoutTokens *t=getTokens(bundle);if(!t.valid)return NO;
 uint64_t packedCard=0,packedKeyboard=0;
 if(active&&(!STHPackRect((STHRect){card.origin.x,card.origin.y,card.size.width,card.size.height},&packedCard)||
             !STHPackRect((STHRect){keyboard.origin.x,keyboard.origin.y,keyboard.size.width,keyboard.size.height},&packedKeyboard)))return NO;
 // Commit invalidated before multi-field write, reader verifies it twice.
 if(notify_set_state(t.commit,0)!=0)return NO;
 if(active){
  if(notify_set_state(t.card,packedCard)!=0||notify_set_state(t.keyboard,packedKeyboard)!=0)return NO;
  uint64_t stamp=(1ULL<<63)|(nowMilliseconds()&0x0000ffffffffffffULL);
  if(notify_set_state(t.commit,stamp)!=0)return NO;
 }
 notify_post(channel(bundle,@"changed").UTF8String);
 if(!t.ackObserved){
  t.ackObserved=YES;int observe=-1;
  notify_register_dispatch(channel(bundle,@"applied").UTF8String,&observe,dispatch_get_main_queue(),^(int n){
   uint64_t ack=0;if(notify_get_state(t.ack,&ack)==0)
    STHWriteLayoutLog([NSString stringWithFormat:@"app-ack bundle=%@ overlap=%.3f applied=%d",bundle,(ack&0xffffffffULL)/8.0,(int)(ack>>63)]);
  });
 }
 return YES;
}

BOOL STHReadLayout(NSString *bundle,CGRect appBounds,CGRect *local,double *overlap) {
 STHLayoutTokens *t=getTokens(bundle);if(!t.valid)return NO;
 uint64_t first=0,last=0,card=0,keyboard=0;
 if(notify_get_state(t.commit,&first)!=0||!(first>>63))return NO;
 uint64_t stamp=first&0x0000ffffffffffffULL,now=nowMilliseconds();
 if(now<stamp||now-stamp>1500)return NO;
 if(notify_get_state(t.card,&card)!=0||notify_get_state(t.keyboard,&keyboard)!=0||
    notify_get_state(t.commit,&last)!=0||last!=first)return NO;
 STHRect out;BOOL ok=STHMapHostedKeyboard(STHUnpackRect(card),STHUnpackRect(keyboard),
  (STHRect){appBounds.origin.x,appBounds.origin.y,appBounds.size.width,appBounds.size.height},&out,overlap);
 if(ok&&local)*local=CGRectMake(out.x,out.y,out.w,out.h);return ok;
}

void STHObserveLayout(NSString *bundle,dispatch_block_t block) {
 STHLayoutTokens *t=getTokens(bundle);if(!t.valid||t.observed!=-1||!block)return;
 int n=-1;uint32_t rc=notify_register_dispatch(channel(bundle,@"changed").UTF8String,&n,dispatch_get_main_queue(),^(int token){block();});
 if(rc==0)t.observed=n;
}
void STHReportLayout(NSString *bundle,double overlap,BOOL applied) {
 STHLayoutTokens *t=getTokens(bundle);if(!t.valid||!isfinite(overlap)||overlap<0)return;
 uint64_t ack=((uint64_t)llround(overlap*8)&0xffffffffULL)|(applied?(1ULL<<63):0);
 if(notify_set_state(t.ack,ack)==0)notify_post(channel(bundle,@"applied").UTF8String);
}
