#import "LayoutBus.h"
#import "LayoutProbe.h"
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <syslog.h>

@interface STHLayoutTokens : NSObject
@property int card0;
@property int card1;
@property int keys0;
@property int keys1;
@property int commit;
@property int preview;
@property int ack;
@property int appScene;
@property int appFrame;
@property int editorFrame;
@property int editorState;
@property int observed;
@property BOOL valid;
@property BOOL ackObserved;
@property BOOL writerActive;
@property uint64_t serial;
@property uint64_t lastCard;
@property uint64_t lastKeys;
@end
@implementation STHLayoutTokens
@end
static NSMutableDictionary<NSString *,STHLayoutTokens *> *tokens;
static NSString *channel(NSString *bundle,NSString *field) {
 return [NSString stringWithFormat:@"com.nx.stheno.layout.v4.%@.%@",bundle,field];
}
static int registerState(NSString *bundle,NSString *field) {
 int token=-1;if(notify_register_check(channel(bundle,field).UTF8String,&token)!=0)return -1;return token;
}
static STHLayoutTokens *getTokens(NSString *bundle) {
 if(![bundle isKindOfClass:NSString.class]||bundle.length==0||bundle.length>160)return nil;
 NSCharacterSet *invalid=[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"] invertedSet];
 if([bundle rangeOfCharacterFromSet:invalid].location!=NSNotFound)return nil;
 if(!tokens)tokens=[NSMutableDictionary new];
 STHLayoutTokens *t=tokens[bundle];if(t)return t;
 t=[STHLayoutTokens new];t.observed=-1;
 t.card0=registerState(bundle,@"card0");t.card1=registerState(bundle,@"card1");
 t.keys0=registerState(bundle,@"keys0");t.keys1=registerState(bundle,@"keys1");
 t.preview=registerState(bundle,@"preview");
 t.commit=registerState(bundle,@"commit");t.ack=registerState(bundle,@"ack");
 t.editorFrame=registerState(bundle,@"editorFrame");t.editorState=registerState(bundle,@"editorState");
 t.appScene=registerState(bundle,@"appScene");t.appFrame=registerState(bundle,@"appFrame");
 t.valid=t.card0>=0&&t.card1>=0&&t.keys0>=0&&t.keys1>=0&&t.commit>=0&&t.ack>=0;
 tokens[bundle]=t;return t;
}
void STHWriteLayoutLog(NSString *line) {
 if(![line isKindOfClass:NSString.class])return;
 NSString *text=[NSString stringWithFormat:@"%.3f %@ %@\n",CACurrentMediaTime(),NSBundle.mainBundle.bundleIdentifier,line];
 NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];
 NSArray *paths=@[@"/var/mobile/Documents/SthenoKeyboardLayout.log",
  [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/SthenoKeyboardLayout.log"],
  [NSTemporaryDirectory() stringByAppendingPathComponent:@"SthenoKeyboardLayout.log"]];
 for(NSString *path in paths){@try{
  NSFileManager *fm=NSFileManager.defaultManager;
  [fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
  NSDictionary *attr=[fm attributesOfItemAtPath:path error:NULL];
  if([attr[NSFileSize] unsignedLongLongValue]>524288)[fm removeItemAtPath:path error:NULL];
  if(![fm fileExistsAtPath:path]&&![fm createFileAtPath:path contents:nil attributes:@{NSFilePosixPermissions:@0600}])continue;
  NSFileHandle *f=[NSFileHandle fileHandleForWritingAtPath:path];if(!f)continue;
  [f seekToEndOfFile];[f writeData:data];[f closeFile];return;
 }@catch(NSException *e){}}
 syslog(LOG_NOTICE,"Stheno keyboard layout: %s",line.UTF8String);
}
static uint64_t nowMilliseconds(void){return (uint64_t)(CACurrentMediaTime()*1000.0);}
static BOOL recent(uint64_t state){uint64_t stamp=state&0x0000ffffffffffffULL,now=nowMilliseconds();return (state>>63)&&now>=stamp&&now-stamp<=1500;}
int STHLayoutStatus(NSString *bundle){
 STHLayoutTokens *t=getTokens(bundle);uint64_t commit=0;
 if(!t.valid||notify_get_state(t.commit,&commit)!=0||!recent(commit))return 0;
 return (commit&(1ULL<<61))?2:1;
}
BOOL STHBeginLayout(NSString *bundle){
 STHLayoutTokens *t=getTokens(bundle);if(!t.valid)return NO;
 t.writerActive=NO;t.lastCard=0;t.lastKeys=0;
 uint64_t value=(1ULL<<63)|(1ULL<<61)|((++t.serial&0x1fffULL)<<48)|(nowMilliseconds()&0x0000ffffffffffffULL);
 if(notify_set_state(t.commit,value)!=0)return NO;
 notify_post(channel(bundle,@"changed").UTF8String);return YES;
}
BOOL STHPublishLayout(NSString *bundle,CGRect card,CGRect keyboard,BOOL active){
 STHLayoutTokens *t=getTokens(bundle);if(!t.valid)return NO;
 if(!active){t.writerActive=NO;notify_set_state(t.commit,0);notify_post(channel(bundle,@"changed").UTF8String);return YES;}
 uint64_t a=0,b=0;
 if(!STHPackRect((STHRect){card.origin.x,card.origin.y,card.size.width,card.size.height},&a)||
    !STHPackRect((STHRect){keyboard.origin.x,keyboard.origin.y,keyboard.size.width,keyboard.size.height},&b))return NO;
 BOOL changed=!t.writerActive||a!=t.lastCard||b!=t.lastKeys;
 if(changed){
  // Write inactive slot, then flip one commit word. NEVER publish commit=0
  // during an active update: that caused scope/fallback races every100ms.
  t.serial++;
  int slot=t.serial&1;
  if(notify_set_state(slot?t.card1:t.card0,a)!=0||notify_set_state(slot?t.keys1:t.keys0,b)!=0)return NO;
 }
 uint64_t commit=(1ULL<<63)|((t.serial&1)<<62)|((t.serial&0x1fffULL)<<48)|(nowMilliseconds()&0x0000ffffffffffffULL);
 if(notify_set_state(t.commit,commit)!=0)return NO;
 t.lastCard=a;t.lastKeys=b;t.writerActive=YES;
 if(changed)notify_post(channel(bundle,@"changed").UTF8String); // heartbeat is silent
 if(!t.ackObserved){
  STHObserveLayoutProbe(bundle);
  t.ackObserved=YES;int observed=-1;
  notify_register_dispatch(channel(bundle,@"applied").UTF8String,&observed,dispatch_get_main_queue(),^(int n){
   uint64_t ack=0,scene=0,frame=0;
   notify_get_state(t.appScene,&scene);notify_get_state(t.appFrame,&frame);notify_get_state(t.ack,&ack);
   STHRect s=STHUnpackRect(scene),f=STHUnpackRect(frame);
   STHWriteLayoutLog([NSString stringWithFormat:@"app-ack bundle=%@ overlap=%.3f computed=%d scene={%.3f,%.3f,%.3f,%.3f} notice={%.3f,%.3f,%.3f,%.3f}",bundle,(ack&0xffffffffULL)/8.0,(int)(ack>>63),s.x,s.y,s.w,s.h,f.x,f.y,f.w,f.h]);
  });
  int editorObserve=-1;
  notify_register_dispatch(channel(bundle,@"editorMeasured").UTF8String,&editorObserve,dispatch_get_main_queue(),^(int n){
   uint64_t before=0,after=0,rect=0;
   notify_get_state(t.editorState,&before);notify_get_state(t.editorFrame,&rect);notify_get_state(t.editorState,&after);
   if(before!=after||!(after>>63))return;
   STHRect f=STHUnpackRect(rect);
   int stage=(after>>48)&255;double key=(int16_t)(after&65535)/8.0;
   double lift=(int16_t)((after>>16)&65535)/8.0;unsigned rows=(after>>32)&255;
   STHWriteLayoutLog([NSString stringWithFormat:@"editor-report bundle=%@ stage=%d frame={%.3f,%.3f,%.3f,%.3f} keysTop=%.3f appliedLift=%.3f rows=%u (measured when stage4/5)",bundle,stage,f.x,f.y,f.w,f.h,key,lift,rows]);
  });
 }
 return YES;
}
BOOL STHReadLayout(NSString *bundle,CGRect appBounds,CGRect *local,double *overlap){
 STHLayoutTokens *t=getTokens(bundle);if(!t.valid)return NO;
 for(int attempt=0;attempt<3;attempt++){
  uint64_t first=0,last=0,card=0,keys=0;
  if(notify_get_state(t.commit,&first)!=0||!recent(first)||(first&(1ULL<<61)))return NO;
  BOOL slot=(first>>62)&1;
  if(notify_get_state(slot?t.card1:t.card0,&card)!=0||notify_get_state(slot?t.keys1:t.keys0,&keys)!=0)return NO;
  if(notify_get_state(t.commit,&last)!=0)return NO;
  if(first!=last)continue;
  STHRect out;BOOL ok=STHMapHostedKeyboard(STHUnpackRect(card),STHUnpackRect(keys),
   (STHRect){appBounds.origin.x,appBounds.origin.y,appBounds.size.width,appBounds.size.height},&out,overlap);
  if(ok&&local)*local=CGRectMake(out.x,out.y,out.w,out.h);return ok;
 }
 return NO;
}
void STHObserveLayout(NSString *bundle,dispatch_block_t block){
 STHLayoutTokens *t=getTokens(bundle);if(!t.valid||t.observed!=-1||!block)return;
 int n=-1;if(notify_register_dispatch(channel(bundle,@"changed").UTF8String,&n,dispatch_get_main_queue(),^(int token){block();})==0)t.observed=n;
}
void STHReportLayout(NSString *bundle,double overlap,BOOL applied){
 STHLayoutTokens *t=getTokens(bundle);if(!t.valid||!isfinite(overlap)||overlap<0)return;
 uint64_t ack=((uint64_t)llround(overlap*8)&0xffffffffULL)|(applied?(1ULL<<63):0);
 if(notify_set_state(t.ack,ack)==0)notify_post(channel(bundle,@"applied").UTF8String);
}
void STHReportNotificationFrame(NSString *bundle,CGRect scene,CGRect frame){
 STHLayoutTokens *t=getTokens(bundle);if(!t.valid)return;
 uint64_t a=0,b=0;
 if(STHPackRect((STHRect){scene.origin.x,scene.origin.y,scene.size.width,scene.size.height},&a))notify_set_state(t.appScene,a);
 if(STHPackRect((STHRect){frame.origin.x,frame.origin.y,frame.size.width,frame.size.height},&b))notify_set_state(t.appFrame,b);
}

BOOL STHPreviewLayout(NSString *bundle,CGRect card){
 STHLayoutTokens *t=getTokens(bundle);uint64_t bits=0;
 if(!t.valid||t.preview<0||!STHPackRect((STHRect){card.origin.x,card.origin.y,card.size.width,card.size.height},&bits))return NO;
 if(notify_set_state(t.preview,bits)!=0)return NO;
 return STHBeginLayout(bundle);
}
BOOL STHReadPreview(NSString *bundle,CGRect keys,CGRect scene,CGRect *local,double *inset){
 STHLayoutTokens *t=getTokens(bundle);uint64_t a=0,b=0,card=0;
 if(!t.valid||notify_get_state(t.commit,&a)!=0||!recent(a)||!(a&(1ULL<<61)))return NO;
 if(notify_get_state(t.preview,&card)!=0||notify_get_state(t.commit,&b)!=0||a!=b)return NO;
 STHRect c=STHUnpackRect(card),out;
 // Match low-card visibility protection used by Keyboard.m, now that keyboard
 // target is known. No text or arbitrary toolbar height is assumed.
 double room=fmin(120.0,c.h*.25),limit=fmax(0,keys.origin.y-room);
 if(c.y>limit)c.y=limit;
 if(!STHMapHostedKeyboard(c,(STHRect){keys.origin.x,keys.origin.y,keys.size.width,keys.size.height},
  (STHRect){scene.origin.x,scene.origin.y,scene.size.width,scene.size.height},&out,inset))return NO;
 if(local)*local=CGRectMake(out.x,out.y,out.w,out.h);return YES;
}

void STHReportEditor(NSString *bundle,int stage,CGRect frame,double top,double lift,unsigned rows){
 STHLayoutTokens *t=getTokens(bundle);if(!t.valid||t.editorFrame<0||t.editorState<0||!isfinite(top)||!isfinite(lift))return;
 static uint64_t sequence;
 uint64_t r=0;
 if(frame.size.width>1&&frame.size.height>1&&!STHPackRect((STHRect){frame.origin.x,frame.origin.y,frame.size.width,frame.size.height},&r))return;
 uint16_t k=(uint16_t)(int16_t)llround(fmax(-4095,fmin(4095,top))*8);
 uint16_t l=(uint16_t)(int16_t)llround(fmax(-4095,fmin(4095,lift))*8);
 uint64_t state=(1ULL<<63)|((uint64_t)(stage&255)<<48)|((++sequence&127)<<40)|((uint64_t)(rows&255)<<32)|((uint64_t)l<<16)|k;
 notify_set_state(t.editorState,0);notify_set_state(t.editorFrame,r);notify_set_state(t.editorState,state);
 notify_post(channel(bundle,@"editorMeasured").UTF8String);
}

BOOL STHReadLayoutUsingKeyboard(NSString *bundle,CGRect scene,CGRect keys,CGRect *mapped,double *inset){
 STHLayoutTokens *t=getTokens(bundle);if(!t.valid)return NO;
 for(int attempt=0;attempt<3;attempt++){
  uint64_t a=0,b=0,card=0;
  if(notify_get_state(t.commit,&a)!=0||!recent(a)||(a&(1ULL<<61)))return NO;
  BOOL slot=(a>>62)&1;
  if(notify_get_state(slot?t.card1:t.card0,&card)!=0||notify_get_state(t.commit,&b)!=0)return NO;
  if(a!=b)continue;
  STHRect out;
  BOOL ok=STHMapHostedKeyboard(STHUnpackRect(card),(STHRect){keys.origin.x,keys.origin.y,keys.size.width,keys.size.height},
   (STHRect){scene.origin.x,scene.origin.y,scene.size.width,scene.size.height},&out,inset);
  if(ok&&mapped)*mapped=CGRectMake(out.x,out.y,out.w,out.h);return ok;
 }
 return NO;
}

BOOL STHReadPhysicalLayout(NSString *bundle,CGRect *cardOut,CGRect *keysOut){
 STHLayoutTokens *t=getTokens(bundle);if(!t.valid)return NO;
 for(int attempt=0;attempt<3;attempt++){
  uint64_t first=0,last=0,c=0,k=0;
  if(notify_get_state(t.commit,&first)!=0||!recent(first)||(first&(1ULL<<61)))return NO;
  BOOL slot=(first>>62)&1;
  if(notify_get_state(slot?t.card1:t.card0,&c)!=0||notify_get_state(slot?t.keys1:t.keys0,&k)!=0)return NO;
  if(notify_get_state(t.commit,&last)!=0)return NO;if(first!=last)continue;
  STHRect a=STHUnpackRect(c),b=STHUnpackRect(k);if(!STHFiniteRect(a)||!STHFiniteRect(b))return NO;
  if(cardOut)*cardOut=CGRectMake(a.x,a.y,a.w,a.h);
  if(keysOut)*keysOut=CGRectMake(b.x,b.y,b.w,b.h);return YES;
 }
 return NO;
}
