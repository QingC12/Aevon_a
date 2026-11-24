// Geometry-only evidence. Never inspect text, accessibility values or view descriptions.
#import "ViewportDiagnostics.h"
#import <sys/stat.h>
#import <unistd.h>
#import <stdio.h>
#import <os/lock.h>
NSDictionary *STHVRectJSON(STHVRect r){
 if(!isfinite(r.x)||!isfinite(r.y)||!isfinite(r.w)||!isfinite(r.h))return @{@"valid":@NO};
 return @{@"x":@(r.x),@"y":@(r.y),@"w":@(r.w),@"h":@(r.h)};
}
// The log is the only durable trace of a keyboard session, so it keeps every
// record. Both limits that used to exist were lossy in the worst possible way:
// a per process line budget silenced every later session, and a 768 KB ceiling
// truncated the file, deleting the session that would have explained a failure.
// There is no budget, no ceiling and no rotation; the record is append only.
// A single write per record per sink keeps interleaved processes readable.
static FILE *logSinks[4];
static int logSinkCount=-1;
static NSString *logPrimaryPath;
static os_unfair_lock logLock=OS_UNFAIR_LOCK_INIT;
static uint64_t logSequence;
static void openSinks(void){
 if(logSinkCount>0)return;
 logSinkCount=0;
 NSString *leaf=@"SthenoViewport33.log";
 NSArray<NSString *> *paths=@[[@"/var/mobile/Documents" stringByAppendingPathComponent:leaf],
  [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/SthenoViewport33.log"],
  [NSTemporaryDirectory() stringByAppendingPathComponent:leaf]];
 NSMutableSet<NSString *> *seen=[NSMutableSet set];
 for(NSString *path in paths){
  if([seen containsObject:path])continue;[seen addObject:path];
  NSFileManager *manager=NSFileManager.defaultManager;
  NSString *folder=path.stringByDeletingLastPathComponent;
  if(![manager fileExistsAtPath:folder])[manager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
  const char *raw=path.fileSystemRepresentation;
  FILE *file=fopen(raw,"ab");
  if(!file)continue;
  chmod(raw,0600);
  setvbuf(file,NULL,_IONBF,0);
  logSinks[logSinkCount++]=file;
  if(!logPrimaryPath)logPrimaryPath=path;
  if(logSinkCount>=(int)(sizeof(logSinks)/sizeof(logSinks[0])))break;
 }
}
void STHVLog(NSString *event,NSString *bundle,NSDictionary *values){
 os_unfair_lock_lock(&logLock);
 openSinks();
 NSMutableDictionary *record=[NSMutableDictionary dictionaryWithDictionary:values?:@{}];
 record[@"event"]=event?:@"unknown";record[@"bundle"]=bundle?:@"unknown";
 record[@"build"]=@"2.0.47";record[@"uptime"]=@(NSProcessInfo.processInfo.systemUptime);
 // seq orders records across threads and across processes only within one
 // process; pid is what separates a springboard session from an app session.
 record[@"seq"]=@(++logSequence);record[@"pid"]=@(getpid());
 record[@"main"]=@(NSThread.isMainThread);
 record[@"process"]=NSProcessInfo.processInfo.processName?:@"unknown";
 // The first record of a process names the file it landed in, so a session that
 // wrote into an app container can still be found from any other copy.
 if(logSequence==1&&logPrimaryPath.length)record[@"sink"]=logPrimaryPath;
 NSError *error=nil;NSData *json=[NSJSONSerialization dataWithJSONObject:record options:0 error:&error];
 if(json&&!error){
  NSMutableData *line=[json mutableCopy];[line appendBytes:"\n" length:1];
  for(int i=0;i<logSinkCount;i++)fwrite(line.bytes,1,line.length,logSinks[i]);
 }
 os_unfair_lock_unlock(&logLock);
}
