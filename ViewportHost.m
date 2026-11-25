// One card geometry authority. Original keyboard avoidance is not called.
#if !defined(STH_VIEWPORT_HOST_TEST)
#import <UIKit/UIKit.h>
#else
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#endif
#import "ViewportHost.h"
#import "ViewportBus.h"
#import "ViewportAuthority.h"
#import "ViewportDiagnostics.h"
#import "ScreenAwake.h"
#import "SceneIntercept.h"
extern void *STHDockCopyFloating(void);
extern size_t STHChooserManagersCount(void *);
extern void *STHChooserCopyManagerAt(size_t,void *);
extern void STHChooserReleaseArray(void *),STHChooserReleaseSwift(void *);
extern void *STHSystemCopyModelIdentifier(void *);
extern BOOL STHNativeMinimized(void *);
extern NSUInteger STHNativeOrientation(void *);
extern CGRect STHNativeRect(void *);
extern double STHNativeGetScale(void *);
extern CGSize STHNativeGetOffset(void *);
extern void STHNativeSetViewportGeometry(void *,const double *);
extern void STHNativeRefreshGeometry(void *);
extern void STHCenterRunAnimation(void (^block)(void),int);
extern void STHGestureInputFocusChanged(void *);
extern BOOL STHSystemActionsEnabled(void);
extern BOOL STHSystemActionRuntimeReady(void);

static __weak id viewportOwner;
static NSString *ownerBundle;
static STHVRect originalCard,currentTarget,physicalKeyboard;
static double originalGeometry[3],writtenGeometry[3],lastOwnerAt;
static BOOL hasWrittenGeometry,localInput,manualOverride;
static BOOL sbKeyboardVisible;
static double keyboardShownAt;
static uint64_t sbPhysicalGeneration;
static uint64_t localBarrierKey,localBarrierEvent;
static STHVRect ownerKeyboard;
static NSSet<NSString *> *publishedBundles;
static BOOL processing;
static double awakeMissingAt;
static NSMutableDictionary<NSString *,NSDictionary *> *lastProbes;
static NSMutableDictionary<NSString *,NSString *> *lastSkips;
// Every refusal used to be a silent return, so a session that never lifted the
// card left no evidence at all. The reason is logged once per bundle: a refusal
// that repeats every registry beat is one fact, not a stream of them.
static void skipOwner(NSString *bundle,NSString *reason,STHVRect keyboard){
 if(!lastSkips)lastSkips=[NSMutableDictionary new];
 if([lastSkips[bundle] isEqual:reason])return;
 lastSkips[bundle]=reason;
 STHVLog(@"host-owner-skip",bundle,@{@"reason":reason,@"physicalKeyboard":STHVRectJSON(keyboard),@"physicalGeneration":@(sbPhysicalGeneration),@"visible":@(sbKeyboardVisible),@"owner":ownerBundle?:@"-"});
}
static void recordProbe(NSString *bundle){
 // Nothing here feeds geometry: it publishes a probe and a log line. With the
 // keyboard evidence switched off this costs a branch instead of two shared
 // memory reads on every registry beat.
 if(!STHVDiagnosticsEnabled())return;
 static NSMutableDictionary *lastFrames;STHVSnapshot frame={0};
 if(STHVReadClientFrames(bundle,&frame)){
  if(!lastFrames)lastFrames=[NSMutableDictionary new];
  if([lastFrames[bundle] unsignedLongLongValue]!=frame.serial){lastFrames[bundle]=@(frame.serial);STHVLog(@"client-frame-probe",bundle,@{@"appRawDiagnostic":STHVRectJSON(frame.card),@"mappedScene":STHVRectJSON(frame.keyboard),@"physicalGeneration":@(frame.physicalGeneration),@"probeSerial":@(frame.serial)});}
 }
 STHVRect a={0},p={0};if(!STHVReadProbe(bundle,&a,&p))return;
 NSDictionary *values=@{@"responderScene":STHVRectJSON(a),@"parentScene":STHVRectJSON(p)};
 if(!lastProbes)lastProbes=[NSMutableDictionary new];
 if([lastProbes[bundle] isEqual:values])return;
 lastProbes[bundle]=values;STHVLog(@"app-geometry-probe",bundle,values);
}
static STHVRect vr(CGRect r){return (STHVRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
static CGRect cr(STHVRect r){return CGRectMake(r.x,r.y,r.w,r.h);}
static STHVRect viewportScreen(void){
#if defined(STH_VIEWPORT_HOST_TEST)
 extern STHVRect STHVHostTestScreen(void);return STHVHostTestScreen();
#else
 return vr(UIScreen.mainScreen.fixedCoordinateSpace.bounds);
#endif
}
static double hostNow(void){
#if defined(STH_VIEWPORT_HOST_TEST)
 extern double STHVHostTestNow(void);return STHVHostTestNow();
#else
 return NSProcessInfo.processInfo.systemUptime;
#endif
}
static NSString *modelBundle(void *model){return CFBridgingRelease(STHSystemCopyModelIdentifier(model));}
static NSMutableDictionary<NSString *,NSArray *> *lastPublishedLayout;
static void publishHostLayout(NSString *bundle,BOOL active,STHVRect card,STHVRect unused){
 // This is the only producer of layout physical facts. Requests never enter it.
 id mask=[NSUserDefaults.standardUserDefaults persistentDomainForName:@"com.nx.stheno"][@"SettingMask"];
 BOOL reflow=[mask isKindOfClass:NSNumber.class]&&([mask unsignedLongLongValue]&(1ULL<<31));
 // The registry is read twice a second and most of those beats change nothing.
 // A publish writes five shared slots and posts a Darwin notification, which
 // wakes the carded application and makes it re-read the layout and re-map the
 // keyboard, so an unchanged state costs a full wake up per card per beat for
 // no reason. Only a real change is published, and only a successful publish
 // is remembered: a failed write is retried on the next beat.
 if(!lastPublishedLayout)lastPublishedLayout=[NSMutableDictionary new];
 NSArray *state=@[@(active),@(card.x),@(card.y),@(card.w),@(card.h),
  @(physicalKeyboard.x),@(physicalKeyboard.y),@(physicalKeyboard.w),@(physicalKeyboard.h),
  @(sbPhysicalGeneration),@(sbKeyboardVisible),@(reflow)];
 if([lastPublishedLayout[bundle] isEqual:state])return;
 if(STHVPublishLayoutPolicyState(bundle,active,card,physicalKeyboard,sbPhysicalGeneration,sbKeyboardVisible,reflow))lastPublishedLayout[bundle]=state;
}
static void writeCard(void *model,const double geometry[3],BOOL nativeTransaction){
 if(nativeTransaction){STHNativeSetViewportGeometry(model,geometry);STHNativeRefreshGeometry(model);}
 else{
  double s=geometry[0],x=geometry[1],y=geometry[2];
  STHCenterRunAnimation(^{double target[3]={s,x,y};STHNativeSetViewportGeometry(model,target);STHNativeRefreshGeometry(model);},0);
 }
}
static void restoreOwner(BOOL nativeTransaction,NSString *reason){
 id model=viewportOwner;NSString *bundle=ownerBundle;
 viewportOwner=nil;ownerBundle=nil;
 if(model&&hasWrittenGeometry&&!manualOverride){
  double s=STHNativeGetScale((__bridge void *)model);CGSize p=STHNativeGetOffset((__bridge void *)model);
  double g[3]={s,p.width,p.height};
  if(fabs(s-writtenGeometry[0])<.001)g[0]=originalGeometry[0];
  if(hypot(p.width-writtenGeometry[1],p.height-writtenGeometry[2])<.5){g[1]=originalGeometry[1];g[2]=originalGeometry[2];}
  writeCard((__bridge void *)model,g,nativeTransaction);
  publishHostLayout(bundle,NO,vr(STHNativeRect((__bridge void *)model)),(STHVRect){0});
  STHVLog(@"host-restore",bundle,@{@"reason":reason,@"card":STHVRectJSON(vr(STHNativeRect((__bridge void *)model)))});
 }
 if(model&&manualOverride){STHNativeRefreshGeometry((__bridge void *)model);publishHostLayout(bundle,NO,vr(STHNativeRect((__bridge void *)model)),(STHVRect){0});}
 hasWrittenGeometry=NO;manualOverride=NO;currentTarget=(STHVRect){0};
}
static void applyOwner(void *pointer,NSString *bundle,STHVRect keyboard,uint64_t event,BOOL nativeTransaction){
 id model=(__bridge id)pointer;
 if(localBarrierKey==STHVKey(bundle)&&event<=localBarrierEvent){skipOwner(bundle,@"local-barrier",keyboard);return;}
 if(!sbKeyboardVisible||!sbPhysicalGeneration){skipOwner(bundle,@"no-visible-keyboard",keyboard);return;}
 if(localInput){skipOwner(bundle,@"local-input",keyboard);return;}
 if(STHNativeMinimized(pointer)){skipOwner(bundle,@"minimized",keyboard);return;}
 if(STHNativeOrientation(pointer)!=1){skipOwner(bundle,@"orientation",keyboard);return;}
 STHVRect screen=viewportScreen();if(!STHVKeyboard(keyboard,screen)){skipOwner(bundle,@"not-keyboard-shaped",keyboard);return;}
 if(viewportOwner!=model){
  restoreOwner(nativeTransaction,@"handoff");
  STHNativeRefreshGeometry(pointer);originalCard=vr(STHNativeRect(pointer));
  if(!STHVValid(originalCard)||originalCard.w<80||originalCard.h<80){skipOwner(bundle,@"invalid-card",keyboard);return;}
  originalGeometry[0]=STHNativeGetScale(pointer);CGSize p=STHNativeGetOffset(pointer);
  originalGeometry[1]=p.width;originalGeometry[2]=p.height;
  if(!isfinite(originalGeometry[0])||originalGeometry[0]<=0){skipOwner(bundle,@"invalid-scale",keyboard);return;}
  viewportOwner=model;ownerBundle=bundle;hasWrittenGeometry=NO;manualOverride=NO;
  STHGestureInputFocusChanged(pointer);
 }
 lastOwnerAt=hostNow();ownerKeyboard=keyboard;
 if(hasWrittenGeometry&&!manualOverride){
  double scale=STHNativeGetScale(pointer);CGSize p=STHNativeGetOffset(pointer);
  if(fabs(scale-writtenGeometry[0])>.001||hypot(p.width-writtenGeometry[1],p.height-writtenGeometry[2])>.5)manualOverride=YES;
 }
 if(manualOverride){
  STHNativeRefreshGeometry(pointer);currentTarget=vr(STHNativeRect(pointer));
  publishHostLayout(bundle,YES,currentTarget,keyboard);return;
 }
 STHVRect target=STHVTarget(originalCard,screen,keyboard);
 if(!STHVValid(target)){skipOwner(bundle,@"invalid-target",keyboard);return;}
 if(!hasWrittenGeometry||!STHVNear(target,currentTarget,.5)){
  double factor=target.w/originalCard.w;
  double g[3]={originalGeometry[0]*factor,
   originalGeometry[1]+target.x+target.w/2-(originalCard.x+originalCard.w/2),
   originalGeometry[2]+target.y+target.h/2-(originalCard.y+originalCard.h/2)};
  // Publish the identical mathematical target used by the application bridge.
  // Native keyboard delivery owns this transaction; an IPC wake uses the same
  // original withAnimation ABI only when that transaction is not on this stack.
  publishHostLayout(bundle,YES,target,keyboard);
  writeCard(pointer,g,nativeTransaction);
  for(int i=0;i<3;i++)writtenGeometry[i]=g[i];
  hasWrittenGeometry=YES;currentTarget=target;
  STHVLog(@"host-target",bundle,@{@"nativeTransaction":@(nativeTransaction),@"before":STHVRectJSON(originalCard),@"target":STHVRectJSON(target),@"measured":STHVRectJSON(vr(STHNativeRect(pointer))),@"physicalKeyboard":STHVRectJSON(keyboard),@"physicalGeneration":@(sbPhysicalGeneration),@"source":@"springboard-only",@"screen":STHVRectJSON(screen),@"keyboardTop":@(keyboard.y),@"cardBottom":@(target.y+target.h),@"keyboardClearance":@(keyboard.y-(target.y+target.h))});
 }else publishHostLayout(bundle,YES,currentTarget,keyboard);
}
static void maintainOwner(BOOL nativeTransaction){
 if(!viewportOwner)return;
 STHVSnapshot ended={0};uint64_t key=STHVRequestOwner();BOOL known=STHVReadRequest(ownerBundle,&ended);
 if(known&&!ended.active)restoreOwner(nativeTransaction,@"explicit-input-end");
 else if(key&&key!=STHVKey(ownerBundle))restoreOwner(nativeTransaction,@"external-owner");
 else if(known&&ended.active&&key==STHVKey(ownerBundle))lastOwnerAt=hostNow();
 else if(hostNow()-lastOwnerAt>3.5)restoreOwner(nativeTransaction,@"owner-expired");
}
static void updateRegistry(BOOL nativeTransaction){
 if(processing||!NSThread.isMainThread||!STHSystemActionRuntimeReady())return;processing=YES;
 if(!STHSystemActionsEnabled()){
  restoreOwner(nativeTransaction,@"disabled");
  for(NSString *bundle in publishedBundles){
   publishHostLayout(bundle,NO,(STHVRect){0},(STHVRect){0});
   // Disabling the feature is not a hidden state: an application whose scene
   // was narrowed for a card has to get its own rectangle back, or it stays a
   // small window with no card around it.
   STHSceneInterceptUntrack(bundle);
  }
  publishedBundles=nil;STHScreenAwakeUpdate(0);awakeMissingAt=0;processing=NO;return;
 }
 maintainOwner(nativeTransaction);
 void *array=STHDockCopyFloating();if(!array){
  // A missing registry is not proof that every card closed. Keep the lease
  // during a bounded outage, then fail closed so auto-lock cannot stay off.
  if(STHScreenAwakeHeld()){
   if(!awakeMissingAt)awakeMissingAt=hostNow();
   else if(hostNow()-awakeMissingAt>10){STHScreenAwakeUpdate(0);awakeMissingAt=0;}
  }else awakeMissingAt=0;
  processing=NO;return;
 }
 awakeMissingAt=0;
 NSMutableSet *current=[NSMutableSet new];
 uint64_t key=STHVRequestOwner();
 @try{
  size_t count=STHChooserManagersCount(array);if(count>4096)return;
  for(size_t i=0;i<count;i++){
   void *pointer=STHChooserCopyManagerAt(i,array);if(!pointer)continue;
   @try{
    NSString *bundle=modelBundle(pointer);if(!bundle.length||[current containsObject:bundle])continue;
    BOOL minimized=STHNativeMinimized(pointer);
    if(minimized){if(viewportOwner==(__bridge id)pointer)restoreOwner(nativeTransaction,@"minimized");continue;}
    [current addObject:bundle];recordProbe(bundle);STHVSnapshot request={0};
    if(key==STHVKey(bundle)&&STHVReadRequest(bundle,&request)){
     if(request.active&&STHSystemActionsEnabled()&&!localInput){
      STHVRect keys=physicalKeyboard;
      applyOwner(pointer,bundle,keys,request.event,nativeTransaction);
     }else if(viewportOwner==(__bridge id)pointer)restoreOwner(nativeTransaction,@"input-ended");
    }
    if(viewportOwner==(__bridge id)pointer&&hasWrittenGeometry){
     publishHostLayout(bundle,YES,currentTarget,ownerKeyboard);
    }else{
     STHNativeRefreshGeometry(pointer);STHVRect card=vr(STHNativeRect(pointer));
     if(STHVValid(card)){
      publishHostLayout(bundle,NO,card,(STHVRect){0});
      // The card rectangle is this application's scene. A ratio change happens
      // on a card that has no keyboard, and that is exactly the state in which
      // an application keeps the width it sampled while the card was moving, so
      // the scene is told the new rectangle here rather than through the
      // keyboard transaction, which has its own delivery and its own timing.
      STHSceneInterceptTrack(bundle,card,viewportScreen());
     }
    }
   }@finally{STHChooserReleaseSwift(pointer);}
  }
  if(viewportOwner&&(![current containsObject:ownerBundle]||!STHSystemActionsEnabled()))restoreOwner(nativeTransaction,@"removed-or-disabled");
  // Unavailable reads never change geometry; maintainOwner bounds actual loss.
  for(NSString *bundle in publishedBundles)if(![current containsObject:bundle]){
   publishHostLayout(bundle,NO,(STHVRect){0},(STHVRect){0});
   // A closed card leaves the scened application on the rectangle it was given.
   STHSceneInterceptUntrack(bundle);
  }
  publishedBundles=[current copy];
  // Visible floating cards are the only reason to hold the system awake.
  STHScreenAwakeUpdate(current.count);
 }@finally{STHChooserReleaseArray(array);processing=NO;}
}
void STHViewportSetLocalInput(BOOL active){
 if(!NSThread.isMainThread)return;localInput=active;
 if(active){
  localBarrierKey=STHVRequestOwner();localBarrierEvent=0;
  for(NSString *bundle in publishedBundles)if(STHVKey(bundle)==localBarrierKey){STHVSnapshot request={0};if(STHVReadRequest(bundle,&request))localBarrierEvent=request.event;break;}
  restoreOwner(NO,@"local-input");
 }
}
void STHViewportModelMinimized(void *model){
 if(NSThread.isMainThread&&viewportOwner==(__bridge id)model)restoreOwner(YES,@"dock");
}
void STHViewportModelChanged(void *model){if(NSThread.isMainThread)updateRegistry(NO);}
BOOL STHViewportKeyboardExcludes(CGPoint point){
 return STHVKeyboard(physicalKeyboard,viewportScreen())&&CGRectContainsPoint(cr(physicalKeyboard),point);
}
// A keyboard that is drawn by another process announces its height in steps and
// not always in order: the same visible keyboard is reported first as a short
// trial frame, then taller, and an interleaved report of the previous height can
// arrive after the tall one. Whoever follows the newest frame blindly ends up
// laid out for a keyboard shorter than the one on screen, and the part of the
// card that the short frame left behind the keys is the composer.
// The rule kept here: a frame that grows is adopted at once, a frame that
// shrinks only after it has stayed the latest report for a full second. Nothing
// is written twice for one keyboard, and the state only ever moves toward the
// taller frame unless the shorter one proves itself by persisting.
static NSUInteger settleSerial,shorterSerial;
static STHVRect pendingShorter;
static void commitKeyboard(STHVRect keyboard,BOOL visible,NSString *source){
 BOOL was=sbKeyboardVisible;
 sbPhysicalGeneration++;
 sbKeyboardVisible=visible;
 if(visible&&!was)keyboardShownAt=hostNow();
 physicalKeyboard=visible?keyboard:(STHVRect){0};
 if(STHVDiagnosticsEnabled())STHVLog(@"sb-keyboard-commit",@"com.apple.springboard",@{@"source":source,@"physicalGeneration":@(sbPhysicalGeneration),@"visible":@(sbKeyboardVisible),@"frame":STHVRectJSON(physicalKeyboard),@"owner":ownerBundle?:@"-",@"card":STHVRectJSON(currentTarget),@"screen":STHVRectJSON(viewportScreen()),@"keyboardTop":@(physicalKeyboard.y)});
 if(!visible)restoreOwner(YES,@"physical-hide");
 // This entry is invoked only inside the unmodified original animation ABI.
 updateRegistry(YES);
 // A keyboard may announce itself with a trial frame and only settle a few
 // frames later; the card is re-evaluated once more inside that window so the
 // opening gesture lands aligned instead of waiting for the next event. The
 // re-evaluation is the same idempotent pass: an unchanged target writes
 // nothing, and a newer keyboard frame supersedes this one through the serial.
 NSUInteger serial=++settleSerial;
 if(visible)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,160*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
  if(serial!=settleSerial||!sbKeyboardVisible)return;
  STHVRect before=currentTarget;STHVRect keyboard=physicalKeyboard;
  STHCenterRunAnimation(^{updateRegistry(YES);},0);
  STHVLog(@"host-settle",@"com.apple.springboard",@{@"before":STHVRectJSON(before),@"after":STHVRectJSON(currentTarget),@"keyboard":STHVRectJSON(keyboard),@"changed":@(!STHVNear(before,currentTarget,.5)),@"physicalGeneration":@(sbPhysicalGeneration),@"owner":ownerBundle?:@"-"});
 });
}
void STHViewportPhysicalWill(CGRect frame,BOOL hiding){
 if(!NSThread.isMainThread)return;
 STHVRect requested=vr(frame),screen=viewportScreen();
 if(hiding){shorterSerial++;pendingShorter=(STHVRect){0};commitKeyboard((STHVRect){0},NO,@"physical-hide");return;}
 // Docked, full width and far too short to be keys: this is the trial rectangle
 // the remote keyboard process publishes before its panel is laid out. It is
 // neither a keyboard nor a dismissal, so the state in force is kept and the
 // frame that follows decides. The test has to come before the shape test,
 // because a 75 point strip still passes every other keyboard rule and used to
 // be announced as the keyboard, leaving the composer under the real panel.
 BOOL docked=STHVValid(requested)&&STHVValid(screen)&&requested.w>=0.7*screen.w&&
  fabs((requested.y+requested.h)-(screen.y+screen.h))<=20.0&&requested.y>=screen.y;
 BOOL trial=docked&&requested.h>0&&requested.h<0.18*screen.h;
 if(trial){
  STHVLog(@"sb-keyboard-trial",@"com.apple.springboard",@{@"frame":STHVRectJSON(requested),@"held":STHVRectJSON(physicalKeyboard),@"visible":@(sbKeyboardVisible),@"physicalGeneration":@(sbPhysicalGeneration),@"owner":ownerBundle?:@"-"});
  return;
 }
 BOOL shaped=STHVKeyboard(requested,screen);
 if(!shaped){shorterSerial++;pendingShorter=(STHVRect){0};commitKeyboard((STHVRect){0},NO,@"physical-not-docked");return;}
 if(!sbKeyboardVisible||requested.y<physicalKeyboard.y-0.5){
  shorterSerial++;pendingShorter=(STHVRect){0};
  commitKeyboard(requested,YES,sbKeyboardVisible?@"physical-taller":@"physical-show");
  return;
 }
 if(STHVNear(requested,physicalKeyboard,.5)){commitKeyboard(requested,YES,@"physical-same");return;}
 // Inside the opening window the panel is still being assembled by a process
 // that reports it in pieces, and those pieces arrive out of order: the same
 // keyboard is reported as 369, then 414 with the input method's own tool row,
 // then 333 without it, all inside 90 ms. A report that arrives in that window
 // is not a keyboard change, it is the same panel being described badly, so no
 // shrink of any size is believed until the window closes. This is what lets the
 // first frame the application receives be the final one.
 BOOL opening=sbKeyboardVisible&&(hostNow()-keyboardShownAt<0.30);
 if(opening&&requested.h<physicalKeyboard.h-0.5){
  pendingShorter=requested;
  NSUInteger serial=++shorterSerial;
  STHVLog(@"sb-keyboard-opening-hold",@"com.apple.springboard",@{@"requested":STHVRectJSON(requested),@"held":STHVRectJSON(physicalKeyboard),@"physicalGeneration":@(sbPhysicalGeneration),@"owner":ownerBundle?:@"-"});
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)NSEC_PER_SEC),dispatch_get_main_queue(),^{
   if(serial!=shorterSerial||!sbKeyboardVisible)return;
   commitKeyboard(pendingShorter,YES,@"physical-shorter-settled");
  });
  updateRegistry(YES);
  return;
 }
 CGFloat drop=physicalKeyboard.h-requested.h;
 if(drop>60.0){
  shorterSerial++;pendingShorter=(STHVRect){0};
  commitKeyboard(requested,YES,@"physical-smaller");
  return;
 }
 pendingShorter=requested;
 NSUInteger serial=++shorterSerial;
 STHVLog(@"sb-keyboard-hold",@"com.apple.springboard",@{@"requested":STHVRectJSON(requested),@"held":STHVRectJSON(physicalKeyboard),@"drop":@(drop),@"delay":@1.0,@"physicalGeneration":@(sbPhysicalGeneration),@"owner":ownerBundle?:@"-"});
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)NSEC_PER_SEC),dispatch_get_main_queue(),^{
  if(serial!=shorterSerial||!sbKeyboardVisible)return;
  commitKeyboard(pendingShorter,YES,@"physical-shorter-settled");
 });
 // Keep the owner lease alive for the duration of the hold.
 updateRegistry(YES);
}
#if !defined(STH_VIEWPORT_HOST_TEST)
// A store signed application can neither open /var/mobile/Documents nor look up
// a Mach service that is not in its sandbox profile. Both were tried and both
// were refused, which left the collected file holding springboard records only
// while the decisions lived in containers nobody opened. What it can do is write
// its own container, and this process may read those. The collector copies whole
// records out of them into the shared file, so the decision and the consequence
// finally sit in one place.
static NSMutableDictionary<NSString *,NSNumber *> *collectorOffsets;
static NSMutableArray<NSString *> *collectorFiles;
static NSDate *collectorStarted;
static BOOL collectorDenied;
static NSString *collectorState(void){return @"/var/mobile/Documents/.stheno-collector.json";}
static void collectorLoad(void){
 collectorOffsets=[NSMutableDictionary new];
 NSData *saved=[NSData dataWithContentsOfFile:collectorState()];
 if(!saved)return;
 NSDictionary *parsed=[NSJSONSerialization JSONObjectWithData:saved options:0 error:NULL];
 if(![parsed isKindOfClass:NSDictionary.class])return;
 for(NSString *key in parsed)if([parsed[key] isKindOfClass:NSNumber.class])collectorOffsets[key]=parsed[key];
}
static void collectorSave(void){
 if(!collectorOffsets)return;
 NSData *data=[NSJSONSerialization dataWithJSONObject:collectorOffsets options:0 error:NULL];
 if(data)[data writeToFile:collectorState() atomically:YES];
}
static void collectorRescan(void){
 NSString *root=@"/var/mobile/Containers/Data/Application";
 NSError *error=nil;
 NSArray<NSString *> *names=[NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:&error];
 if(!names){
  if(!collectorDenied){collectorDenied=YES;
   STHVLog(@"collector-denied",@"com.apple.springboard",@{@"root":root,@"error":error.localizedDescription?:@"-"});
  }
  collectorFiles=[NSMutableArray new];
  return;
 }
 NSFileManager *manager=NSFileManager.defaultManager;
 NSMutableArray<NSString *> *found=[NSMutableArray new];
 for(NSString *name in names){
  for(NSString *leaf in @[@"Documents/SthenoViewport33.log",@"tmp/SthenoViewport33.log"]){
   NSString *path=[root stringByAppendingPathComponent:[name stringByAppendingPathComponent:leaf]];
   if([manager fileExistsAtPath:path])[found addObject:path];
  }
 }
 collectorFiles=found;
 STHVLog(@"collector-scan",@"com.apple.springboard",@{@"applications":@(names.count),@"files":@(found.count),@"denied":@(error!=nil)});
}
static void collectorSweep(void){
 if(!collectorFiles)collectorRescan();
 if(!collectorFiles)return;
 NSFileManager *manager=NSFileManager.defaultManager;
 for(NSString *path in collectorFiles){
  NSDictionary *attributes=[manager attributesOfItemAtPath:path error:NULL];
  unsigned long long size=[attributes[NSFileSize] unsignedLongLongValue];
  if(!size)continue;
  NSNumber *known=collectorOffsets[path];
  unsigned long long offset=0;
  if(known)offset=known.unsignedLongLongValue;
  else{
   // A file that predates this session already holds sessions nobody needs
   // twice, so it is adopted at its end; a file created after this springboard
   // started is the current session and is read from the beginning.
   NSDate *modified=attributes[NSFileModificationDate];
   BOOL fresh=collectorStarted&&modified&&[modified compare:collectorStarted]!=NSOrderedAscending;
   offset=fresh?0:size;
   STHVLog(@"collector-adopt",@"com.apple.springboard",@{@"container":[[path stringByDeletingLastPathComponent] stringByDeletingLastPathComponent].lastPathComponent?:@"-",@"size":@(size),@"from":@(offset)});
  }
  if(size<offset){offset=0;STHVLog(@"collector-reset",@"com.apple.springboard",@{@"size":@(size)});}
  if(size<=offset){collectorOffsets[path]=@(offset);continue;}
  NSFileHandle *handle=[NSFileHandle fileHandleForReadingAtPath:path];
  if(!handle)continue;
  NSData *data=nil;
  @try{[handle seekToFileOffset:offset];data=[handle readDataToEndOfFile];}
  @catch(NSException *exception){data=nil;}
  [handle closeFile];
  if(!data.length)continue;
  // Only whole records are copied; a half written line waits for the next sweep.
  const char *bytes=data.bytes;NSUInteger length=data.length,whole=0;
  for(NSUInteger i=0;i<length;i++)if(bytes[i]=='\n')whole=i+1;
  if(!whole)continue;
  STHVLogAppendFromFile([data subdataWithRange:NSMakeRange(0,whole)]);
  collectorOffsets[path]=@(offset+whole);
 }
 collectorSave();
}
static void startCollector(void){
 if(!STHVDiagnosticsEnabled())return;
 static dispatch_source_t timer;
 if(timer)return;
 dispatch_queue_t queue=dispatch_queue_create("com.nx.stheno.viewport32.collector",DISPATCH_QUEUE_SERIAL);
 dispatch_async(queue,^{
  collectorStarted=[NSDate date];
  collectorLoad();
  STHVLog(@"collector-start",@"com.apple.springboard",@{@"known":@(collectorOffsets.count)});
 });
 timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,queue);
 dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,2ull*NSEC_PER_SEC),2ull*NSEC_PER_SEC,200ull*NSEC_PER_MSEC);
 __block NSUInteger ticks=0;
 dispatch_source_set_event_handler(timer,^{
  if(!collectorFiles||ticks%15==0)collectorRescan();
  collectorSweep();
  ticks++;
 });
 dispatch_resume(timer);
}
static BOOL geometryInstalled;
static void installGeometry(NSString *trigger){
 if(geometryInstalled)return;
 // The core image is injected into springboard as well, but dyld order between
 // the two libraries is not fixed. This used to be a single attempt: when the
 // order went the other way the host gave up for the whole springboard session,
 // so a keyboard in a floating card only aligned after several resprings and
 // not on every one of them. Installing late is harmless: nothing below holds
 // state from the moment of loading.
 if(!STHSystemActionRuntimeReady()){STHVLog(@"host-runtime-wait",@"com.apple.springboard",@{@"trigger":trigger});return;}
 geometryInstalled=YES;
 STHVObserveRequests(^{STHCenterRunAnimation(^{updateRegistry(YES);},0);});
 for(NSString *name in @[UIKeyboardWillShowNotification,UIKeyboardWillChangeFrameNotification,UIKeyboardWillHideNotification]){
  [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
   BOOL hide=[note.name isEqualToString:UIKeyboardWillHideNotification];
   id value=note.userInfo[UIKeyboardFrameEndUserInfoKey];
   if([note.object isKindOfClass:UIScreen.class]&&note.object!=UIScreen.mainScreen)return;
   CGRect frame=[value isKindOfClass:NSValue.class]?[value CGRectValue]:CGRectNull;
   if(!CGRectIsNull(frame))frame=[UIScreen.mainScreen.coordinateSpace convertRect:frame toCoordinateSpace:UIScreen.mainScreen.fixedCoordinateSpace];
   BOOL noDockedKeyboard=hide||!STHVKeyboard(vr(frame),viewportScreen());
   if(STHVDiagnosticsEnabled())STHVLog(@"sb-keyboard-notification",@"com.apple.springboard",@{@"notification":note.name,@"nextGeneration":@(sbPhysicalGeneration+1),@"raw":STHVRectJSON(vr(frame)),@"hiding":@(noDockedKeyboard)});
   STHCenterRunAnimation(^{STHViewportPhysicalWill(frame,noDockedKeyboard);},0);
  }];
 }
 static dispatch_source_t registryTimer;registryTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
 // A custom window ratio is applied by the native gesture and geometry path,
 // which does not call into this library, so the only way a hosted application
 // learns the new viewport is this beat. Half a second was enough for the
 // keyboard, which has its own event, but a ratio change reaches the carded app
 // only here: at two beats a second it kept laying out for the previous width
 // long enough for the result to be visible. Publishing is unchanged and still
 // gated on a real difference, so the extra pass costs a registry read and one
 // native rectangle per open card, and writes nothing when nothing moved.
 dispatch_source_set_timer(registryTimer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/4),NSEC_PER_SEC/4,NSEC_PER_SEC/20);
 dispatch_source_set_event_handler(registryTimer,^{updateRegistry(NO);});dispatch_resume(registryTimer);
 STHVLog(@"host-start",@"com.apple.springboard",@{@"architecture":@"viewport32",@"legacyAvoidanceCalled":@NO,@"trigger":trigger});
}
__attribute__((constructor)) static void installViewportHost(void){dispatch_async(dispatch_get_main_queue(),^{
 // The port is opened before anything else, and before the first record is
 // written, so an application that loads later can already reach the file. A
 // sandboxed application cannot open the shared file itself; its records are
 // appended here instead, verbatim, keeping their own pid and process name.
 // Both the port and the collector exist only to move records into one file, so
 // they start together with the recorders. With the evidence switched off at
 // compile time neither is created and springboard holds no timer or port for
 // a feature that is frozen.
 if(STHVDiagnosticsEnabled()){
  STHVLogInstallRelay();
  startCollector();
 }
 // Record only, and only while the evidence is switched on. These observers
 // never write geometry, never publish layout and never run an animation: they
 // answer one question the geometry path cannot, namely whether springboard saw
 // a keyboard at all in a session where the runtime below declined to install.
 // Without them that session left an empty log and could not be compared with a
 // working one. Switched off, they are not registered and cost nothing.
 BOOL runtimeReady=STHSystemActionRuntimeReady();
 STHVLog(@"host-runtime",@"com.apple.springboard",@{@"ready":@(runtimeReady),@"enabled":@(STHSystemActionsEnabled()),@"home":NSHomeDirectory()});
 if(STHVDiagnosticsEnabled())for(NSString *name in @[UIKeyboardWillShowNotification,UIKeyboardDidShowNotification,UIKeyboardWillChangeFrameNotification,UIKeyboardDidChangeFrameNotification,UIKeyboardWillHideNotification,UIKeyboardDidHideNotification]){
  [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
   id value=note.userInfo[UIKeyboardFrameEndUserInfoKey];
   CGRect frame=[value isKindOfClass:NSValue.class]?[value CGRectValue]:CGRectNull;
   STHVLog(@"sb-keyboard-seen",@"com.apple.springboard",@{@"notification":note.name,@"object":note.object?NSStringFromClass([note.object class]):@"-",@"raw":STHVRectJSON(vr(frame)),@"geometryRuntime":@(STHSystemActionRuntimeReady()),@"enabled":@(STHSystemActionsEnabled()),@"visible":@(sbKeyboardVisible),@"generation":@(sbPhysicalGeneration),@"docked":@(!CGRectIsNull(frame)&&STHVKeyboard(vr(frame),viewportScreen())),@"owner":ownerBundle?:@"-"});
  }];
 }
 installGeometry(@"launch");
 if(geometryInstalled)return;
 // Twenty tries at 100 ms covers the loader without leaving a timer behind on
 // springboard for the rest of its life.
 __block int attempts=0;
 dispatch_source_t retry=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
 dispatch_source_set_timer(retry,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),100*NSEC_PER_MSEC,20*NSEC_PER_MSEC);
 dispatch_source_set_event_handler(retry,^{
  installGeometry([NSString stringWithFormat:@"retry-%d",++attempts]);
  if(geometryInstalled||attempts>=20){
   dispatch_source_cancel(retry);
   if(!geometryInstalled)STHVLog(@"host-core-not-ready",@"com.apple.springboard",@{@"attempts":@(attempts)});
  }
 });
 dispatch_resume(retry);
});}
#endif
