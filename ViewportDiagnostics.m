// Geometry-only evidence. Never inspect text, accessibility values or view descriptions.
#import "ViewportDiagnostics.h"
#import <sys/stat.h>
#import <stdio.h>
NSDictionary *STHVRectJSON(STHVRect r){
 if(!isfinite(r.x)||!isfinite(r.y)||!isfinite(r.w)||!isfinite(r.h))return @{@"valid":@NO};
 return @{@"x":@(r.x),@"y":@(r.y),@"w":@(r.w),@"h":@(r.h)};
}
void STHVLog(NSString *event,NSString *bundle,NSDictionary *values){
 static NSUInteger count;
 if(!NSThread.isMainThread||count++>16000)return;
 NSMutableDictionary *record=[NSMutableDictionary dictionaryWithDictionary:values?:@{}];
 record[@"event"]=event?:@"unknown";record[@"bundle"]=bundle?:@"unknown";
 record[@"build"]=@"2.0.31";record[@"uptime"]=@(NSProcessInfo.processInfo.systemUptime);
 NSError *error=nil;NSData *json=[NSJSONSerialization dataWithJSONObject:record options:0 error:&error];
 if(!json||error)return;
 NSMutableData *line=[json mutableCopy];[line appendBytes:"\n" length:1];
 static dispatch_queue_t writer;static dispatch_once_t once;
 dispatch_once(&once,^{writer=dispatch_queue_create("com.nx.stheno.viewport31.geometry-log",DISPATCH_QUEUE_SERIAL);});
 dispatch_async(writer,^{
 NSArray *paths=@[@"/var/mobile/Documents/SthenoViewport31.log",
  [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/SthenoViewport31.log"],
  [NSTemporaryDirectory() stringByAppendingPathComponent:@"SthenoViewport31.log"]];
 NSMutableSet *written=[NSMutableSet new];
 for(NSString *path in paths){
  if([written containsObject:path])continue;[written addObject:path];
  struct stat info;const char *p=path.fileSystemRepresentation;
  BOOL truncate=stat(p,&info)==0&&info.st_size>768*1024;
  FILE *f=fopen(p,truncate?"wb":"ab");if(!f)continue;
  chmod(p,0600);fwrite(line.bytes,1,line.length,f);fclose(f);
 }
 });
}
