// Commit the complete owner lease and physical Will frame before notification.
static int frameToken(NSString *bundle,NSString *part){return token([leaseName(bundle) stringByAppendingFormat:@".%@",part]);}
static uint64_t inputNow(void){return (uint64_t)(NSProcessInfo.processInfo.systemUptime*1000.0);}
static uint64_t inputReadFloor;
void STHResetInputFocusReadEpoch(void){inputReadFloor=inputNow();}
static BOOL publishSnapshot(NSString *bundle,BOOL active,BOOL hasFrame,STHRect frame){
 if(!NSThread.isMainThread||!bundle.length)return NO;
 uint64_t packed=0;if(hasFrame&&(!STHPackRect(frame,&packed)||frame.w<80||frame.h<80))return NO;
 int global=token(changed),commit=token(leaseName(bundle));if(global<0||commit<0)return NO;
 if(!active){
  // Never read-then-clear the shared owner: a late A hide must not erase B.
  if(notify_set_state(commit,0))return NO;
  return notify_post(changed.UTF8String)==NOTIFY_STATUS_OK;
 }
 static uint64_t serial;uint64_t sequence=++serial;
 if(hasFrame){
  int data=frameToken(bundle,(sequence&1)?@"frame1":@"frame0");
  if(data<0||notify_set_state(data,packed))return NO;
 }
 uint64_t value=(1ULL<<63)|((sequence&1ULL)<<62)|(hasFrame?(1ULL<<61):0)|((sequence&0x1fffULL)<<48)|(inputNow()&0x0000ffffffffffffULL);
 if(notify_set_state(commit,value)||notify_set_state(global,bundleKey(bundle)))return NO;
 uint64_t confirmed=0;
 if(notify_get_state(commit,&confirmed)||confirmed!=value)return NO;
 return notify_post(changed.UTF8String)==NOTIFY_STATUS_OK;
}
static BOOL readSnapshot(NSString *bundle,BOOL requireFrame,STHRect *frame){
 if(!NSThread.isMainThread||!bundle.length)return NO;
 int global=token(changed),commit=token(leaseName(bundle));if(global<0||commit<0)return NO;
 for(int attempt=0;attempt<3;attempt++){
  uint64_t ownerBefore=0,ownerAfter=0,first=0,last=0,packed=0;
  if(notify_get_state(global,&ownerBefore)||ownerBefore!=bundleKey(bundle)||notify_get_state(commit,&first)||!(first>>63))return NO;
  uint64_t now=inputNow(),at=first&0x0000ffffffffffffULL;
  if(now<at||at<inputReadFloor||now-at>(requireFrame?750:3000))return NO;
  BOOL hasFrame=(first&(1ULL<<61))!=0;
  if(requireFrame&&!hasFrame)return NO;
  if(hasFrame){
   int data=frameToken(bundle,(first&(1ULL<<62))?@"frame1":@"frame0");
   if(data<0||notify_get_state(data,&packed))return NO;
  }
  if(notify_get_state(commit,&last)||notify_get_state(global,&ownerAfter))return NO;
  if(first!=last||ownerBefore!=ownerAfter)continue;
  if(frame&&hasFrame)*frame=STHUnpackRect(packed);
  return YES;
 }
 return NO;
}
BOOL STHPublishInputKeyboard(NSString *bundle,STHRect frame){return publishSnapshot(bundle,YES,YES,frame);}
BOOL STHReadInputKeyboard(NSString *bundle,STHRect *frame){return readSnapshot(bundle,YES,frame);}
