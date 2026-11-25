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
static BOOL logSharedWritable;
static os_unfair_lock logLock=OS_UNFAIR_LOCK_INIT;
static uint64_t logSequence;
// A sandboxed application cannot open /var/mobile/Documents, and a store
// signature cannot be given the extension that would let it. Its records are
// therefore handed to springboard over a message port and appended there
// verbatim: the record already carries its own pid, process and bundle, so the
// line stays readable in the shared file exactly as it was produced. This is
// the only way one file holds the decision and its consequence together.
#define STHVLogPort "com.nx.stheno.viewport32.log"
static BOOL logRelayHost;
static void relaySend(NSData *line);
static void openSinks(void){
 if(!STHVDiagnosticsEnabled())return;
 if(logSinkCount>0)return;
 logSinkCount=0;
 NSString *leaf=@"SthenoViewport33.log";
 NSString *shared=[@"/var/mobile/Documents" stringByAppendingPathComponent:leaf];
 NSArray<NSString *> *paths=@[shared,
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
  if([path isEqualToString:shared]){
   logSharedWritable=YES;
   // The shared file is the collected one. A second copy inside an application
   // container would be copied back out by the collector and would then appear
   // twice, so it is not written at all when the shared file was opened.
   break;
  }
  if(logSinkCount>=(int)(sizeof(logSinks)/sizeof(logSinks[0])))break;
 }
}
void STHVLog(NSString *event,NSString *bundle,NSDictionary *values){
 if(!STHVDiagnosticsEnabled())return;
 NSData *forward=nil;
 os_unfair_lock_lock(&logLock);
 openSinks();
 NSMutableDictionary *record=[NSMutableDictionary dictionaryWithDictionary:values?:@{}];
 record[@"event"]=event?:@"unknown";record[@"bundle"]=bundle?:@"unknown";
 record[@"build"]=@"2.0.59";record[@"uptime"]=@(NSProcessInfo.processInfo.systemUptime);
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
  // Nothing written here can reach the shared file, so the line travels to the
  // process that can write it. The host never forwards to itself.
  if(!logSharedWritable&&!logRelayHost)forward=line;
 }
 os_unfair_lock_unlock(&logLock);
 if(forward)relaySend(forward);
}
// The record is appended as received, including its own pid and process name, so
// a forwarded line differs from a local one only by those fields.
static void appendForwarded(NSData *line){
 if(!STHVDiagnosticsEnabled())return;
 os_unfair_lock_lock(&logLock);
 openSinks();
 for(int i=0;i<logSinkCount;i++)fwrite(line.bytes,1,line.length,logSinks[i]);
 os_unfair_lock_unlock(&logLock);
}
static void relaySend(NSData *line){
 static dispatch_queue_t queue;
 static dispatch_once_t once;
 static int pending;
 dispatch_once(&once,^{queue=dispatch_queue_create("com.nx.stheno.viewport32.log.relay",DISPATCH_QUEUE_SERIAL);});
 // A stalled reader must not grow a queue without bound; the newest records are
 // the ones that explain a failure, so the oldest excess is dropped instead.
 if(__atomic_add_fetch(&pending,1,__ATOMIC_RELAXED)>8192){
  __atomic_sub_fetch(&pending,1,__ATOMIC_RELAXED);return;
 }
 dispatch_async(queue,^{
  // Confined to the serial queue, so the cached port needs no lock.
  static CFMessagePortRef port;
  static int failures;
  if(failures<=5){
   if(!port){
    port=CFMessagePortCreateRemote(NULL,CFSTR(STHVLogPort));
    if(!port)failures++;
   }
   if(port){
    // The iOS SDK does not declare kCFMessagePortSendNoReply; the constant is a
    // CFString with this exact value and the send compares by value, so the
    // literal selects the same mode. A rejected mode only costs a record.
    SInt32 status=CFMessagePortSendRequest(port,0,(__bridge CFDataRef)line,0.3,0.3,CFSTR("no reply"),NULL);
    if(status!=kCFMessagePortSuccess){CFRelease(port);port=NULL;failures++;}else failures=0;
   }
  }
  __atomic_sub_fetch(&pending,1,__ATOMIC_RELAXED);
 });
}
static CFDataRef relayReceive(CFMessagePortRef port,SInt32 identifier,CFDataRef data,void *info){
 (void)port;(void)identifier;(void)info;
 if(!data)return NULL;
 NSData *line=(__bridge NSData *)data;
 if(!line.length||line.length>16384)return NULL;
 appendForwarded(line);
 // One line per joining process, so a session that ends covered still shows
 // whether the application side was speaking at all.
 static NSMutableSet *pids;
 static BOOL noticed;
 if(!noticed){
  noticed=YES;
  STHVLog(@"log-relay-ready",@"com.apple.springboard",@{@"port":@STHVLogPort});
 }
 NSDictionary *parsed=[NSJSONSerialization JSONObjectWithData:line options:0 error:NULL];
 NSNumber *pid=[parsed isKindOfClass:NSDictionary.class]?parsed[@"pid"]:nil;
 if(![pid isKindOfClass:NSNumber.class])return NULL;
 if(!pids)pids=[NSMutableSet new];
 if([pids containsObject:pid])return NULL;
 [pids addObject:pid];
 STHVLog(@"log-relay-client",@"com.apple.springboard",@{@"originPid":pid,
  @"originProcess":parsed[@"process"]?:@"unknown",@"originBundle":parsed[@"bundle"]?:@"unknown",
  @"originBuild":parsed[@"build"]?:@"unknown"});
 return NULL;
}
void STHVLogAppendFromFile(NSData *data){
 if(!STHVDiagnosticsEnabled())return;
 if(data.length)appendForwarded(data);
}
void STHVLogInstallRelay(void){
 if(!STHVDiagnosticsEnabled())return;
 if(logRelayHost)return;
 logRelayHost=YES;
 if(!NSThread.isMainThread)return;
 // Open the file before the first record so the report below states the truth.
 os_unfair_lock_lock(&logLock);openSinks();BOOL shared=logSharedWritable;os_unfair_lock_unlock(&logLock);
 CFMessagePortRef port=CFMessagePortCreateLocal(NULL,CFSTR(STHVLogPort),relayReceive,NULL,NULL);
 if(!port){
  STHVLog(@"log-relay-listen",@"com.apple.springboard",@{@"port":@STHVLogPort,
   @"sharedWritable":@(shared),@"listening":@NO});
  return;
 }
 CFMessagePortSetDispatchQueue(port,dispatch_get_main_queue());
 STHVLog(@"log-relay-listen",@"com.apple.springboard",@{@"port":@STHVLogPort,
  @"sharedWritable":@(shared),@"listening":@YES});
}
