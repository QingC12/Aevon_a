#import "LayoutBus.h"
#import <QuartzCore/QuartzCore.h>
#import <notify.h>

@interface STHLayoutTokens : NSObject
@property int card0;
@property int card1;
@property int keys0;
@property int keys1;
@property int commit;
@property int preview;
@property int previewCommit;
@property int observed;
@property BOOL valid;
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
 STHLayoutTokens *t=tokens[bundle];
 if(!t) {
  t=[STHLayoutTokens new];t.observed=-1;
  t.card0=registerState(bundle,@"card0");t.card1=registerState(bundle,@"card1");
  t.keys0=registerState(bundle,@"keys0");t.keys1=registerState(bundle,@"keys1");
  t.preview=registerState(bundle,@"preview");t.previewCommit=registerState(bundle,@"preview-commit");
  t.commit=registerState(bundle,@"commit");
  t.valid=t.card0>=0&&t.card1>=0&&t.keys0>=0&&t.keys1>=0&&t.commit>=0;
  tokens[bundle]=t;
 }
 return t;
}
static uint64_t nowMilliseconds(void){return (uint64_t)(CACurrentMediaTime()*1000.0);}
static BOOL recent(uint64_t state){uint64_t stamp=state&0x0000ffffffffffffULL,now=nowMilliseconds();return (state>>63)&&now>=stamp&&now-stamp<=1500;}
int STHLayoutStatus(NSString *bundle){
 STHLayoutTokens *t=getTokens(bundle);uint64_t commit=0;
 if(!t.valid||notify_get_state(t.commit,&commit)!=0||!recent(commit))return 0;
 return (commit&(1ULL<<61))?2:1;
}
static BOOL beginLayout(NSString *bundle,uint64_t previewValue,BOOL hasPreview){
 STHLayoutTokens *t=getTokens(bundle);if(!t.valid)return NO;
 t.writerActive=NO;t.lastCard=0;t.lastKeys=0;
 if(hasPreview){
  if(t.preview<0||t.previewCommit<0||notify_set_state(t.previewCommit,0)!=0||notify_set_state(t.preview,previewValue)!=0)return NO;
 }
 uint64_t value=(1ULL<<63)|(1ULL<<61)|((++t.serial&0x1fffULL)<<48)|(nowMilliseconds()&0x0000ffffffffffffULL);
 if(notify_set_state(t.commit,value)!=0)return NO;
 if(hasPreview&&notify_set_state(t.previewCommit,value)!=0)return NO;
 notify_post(channel(bundle,@"changed").UTF8String);return YES;
}
BOOL STHBeginLayout(NSString *bundle){return beginLayout(bundle,0,NO);}
BOOL STHPublishLayout(NSString *bundle,CGRect card,CGRect keyboard,BOOL active){
 STHLayoutTokens *t=getTokens(bundle);if(!t.valid)return NO;
 if(!active){
  t.writerActive=NO;
  if(notify_set_state(t.commit,0)!=0)return NO;
  if(t.previewCommit>=0)notify_set_state(t.previewCommit,0);
  notify_post(channel(bundle,@"changed").UTF8String);return YES;
 }
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

BOOL STHPreviewLayout(NSString *bundle,CGRect card){
 STHLayoutTokens *t=getTokens(bundle);uint64_t bits=0;
 if(!t.valid||!STHPackRect((STHRect){card.origin.x,card.origin.y,card.size.width,card.size.height},&bits))return NO;
 return beginLayout(bundle,bits,YES);
}
BOOL STHReadPreview(NSString *bundle,CGRect keys,CGRect scene,CGRect *local,double *inset){
 STHLayoutTokens *t=getTokens(bundle);uint64_t a=0,b=0,card=0,previewCommit=0,previewCommitAfter=0;
 if(!t.valid||t.previewCommit<0||notify_get_state(t.commit,&a)!=0||!recent(a)||!(a&(1ULL<<61)))return NO;
 if(notify_get_state(t.previewCommit,&previewCommit)!=0||previewCommit!=a||notify_get_state(t.preview,&card)!=0||
    notify_get_state(t.commit,&b)!=0||notify_get_state(t.previewCommit,&previewCommitAfter)!=0||a!=b||previewCommitAfter!=a)return NO;
 STHRect c=STHUnpackRect(card),out;
 // Match low-card visibility protection used by Keyboard.m, now that keyboard
 // target is known. No text or arbitrary toolbar height is assumed.
 double room=fmin(120.0,c.h*.25),limit=fmax(0,keys.origin.y-room);
 if(c.y>limit)c.y=limit;
 if(!STHMapHostedKeyboard(c,(STHRect){keys.origin.x,keys.origin.y,keys.size.width,keys.size.height},
  (STHRect){scene.origin.x,scene.origin.y,scene.size.width,scene.size.height},&out,inset))return NO;
 if(local)*local=CGRectMake(out.x,out.y,out.w,out.h);return YES;
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
