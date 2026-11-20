// Read-only native catalog snapshots and transient (not pinned) App launch.
#import <Foundation/Foundation.h>
#import "ChooserSelection.h"
#include <stdint.h>
#include <string.h>
extern uintptr_t sth_action_core_base;
extern BOOL STHSystemActionRuntimeReady(void);
// Existing bridges, do not redefine them:
extern void STHSystemMakeSwiftString(NSString *, uintptr_t outWords[2]);
extern void *STHSystemCopySwiftString(const uintptr_t words[2]);
extern void *STHSystemCopyModelIdentifier(void *borrowedModel);
// ChooserLaunchNative.S:
extern void *STHChooserBuildManagerConsumed(uintptr_t, uintptr_t);
extern void STHChooserOpenModelAnimated(void *borrowedModel);
extern int STHChooserCopyCatalogs(void *ownedArraysOut[2]);
extern void *STHChooserCopyPinnedManagers(void);
extern size_t STHChooserManagersCount(void *borrowedArray);
extern void *STHChooserCopyManagerAt(size_t, void *borrowedArray);
extern void STHChooserReleaseSwift(void *ownedModel);
extern void STHChooserReleaseArray(void *ownedArray);

typedef struct { uintptr_t word[2]; } STStringWords;
typedef struct { STStringWords name, identifier; } STApp32;
_Static_assert(sizeof(STApp32)==32,"Original Stheno.App stride must stay 32");

// This is an additional runtime fingerprint, NOT a substitute for the build's
// complete binary/hash/range gate. RuntimeReady alone only checks name+arch.
BOOL STHChooserImageReady(void) {
 if(!STHSystemActionRuntimeReady()) return NO;
#if defined(STH_CHOOSER_TEST)
 return YES;
#else
 static const struct { uintptr_t rva; unsigned char bytes[16]; } gates[]={
  {0x4e024,{0x7f,0x23,0x03,0xd5,0xff,0x03,0x05,0xd1,0xe9,0x23,0x0d,0x6d,0xfc,0x6f,0x0e,0xa9}},
  {0x7ea40,{0x7f,0x23,0x03,0xd5,0xff,0x03,0x01,0xd1,0xf6,0x57,0x01,0xa9,0xf4,0x4f,0x02,0xa9}},
  {0x65af4,{0x7f,0x23,0x03,0xd5,0xfd,0x7b,0xbf,0xa9,0xfd,0x03,0x00,0x91,0xe0,0x03,0x14,0xaa}},
  {0x58944,{0x7f,0x23,0x03,0xd5,0xf6,0x0f,0x1d,0xf8,0xf4,0x4f,0x01,0xa9,0xfd,0x7b,0x02,0xa9}},
  {0x51454,{0x7f,0x23,0x03,0xd5,0xff,0x03,0x01,0xd1,0xf4,0x4f,0x02,0xa9,0xfd,0x7b,0x03,0xa9}},
  {0x47e8, {0xc6,0x53,0x03,0x14,0xff,0x03,0x03,0xd1,0xfc,0x6f,0x06,0xa9,0xfa,0x67,0x07,0xa9}}
 };
 for(size_t i=0;i<sizeof(gates)/sizeof(gates[0]);i++)
  if(memcmp((const void *)(sth_action_core_base+gates[i].rva),gates[i].bytes,16))return NO;
 return YES;
#endif
}
static BOOL isVirtualAction(NSString *s) {
 return [s isEqualToString:@"com.nx.stheno.action.screenshot"] ||
        [s isEqualToString:@"com.nx.stheno.action.screen-recording"];
}
// App arrays are original native Array<App> (not NSArray). Fail closed on any
// representation other than the verified native buffer; never guess layout.
static BOOL appCount(void *array,size_t *count) {
 uintptr_t bits=(uintptr_t)array;
 if(!bits || (bits>>62) || (bits&7))return NO;
 const uintptr_t *h=array;
 size_t n=h[2],capacity=h[3]>>1;
 if(n>65536 || n>capacity)return NO;
 *count=n; return YES;
}

// nil means native catalog/selected-state is unavailable; [] means no matches.
// Main-thread, synchronous, retained native snapshots -> immutable Foundation
// values. There is NO pinning, AppStorage setter, Apps parse or preference write.
NSArray<NSDictionary<NSString *,NSString *> *> *STHChooserSnapshotUnpinned(void) {
 if(!NSThread.isMainThread || !STHChooserImageReady())return nil;
 void *catalogs[2]={0};
 if(!STHChooserCopyCatalogs(catalogs))return nil;
 void *managers=STHChooserCopyPinnedManagers();
 if(!managers) {
  STHChooserReleaseArray(catalogs[0]);
  STHChooserReleaseArray(catalogs[1]);
  return nil;
 }
 @try {
  size_t counts[2]={0};
  if(!appCount(catalogs[0],&counts[0]) || !appCount(catalogs[1],&counts[1]))return nil;
  size_t n=STHChooserManagersCount(managers);
  if(n>65536)return nil;
  NSMutableSet<NSString *> *pinned=[NSMutableSet set];
  for(size_t i=0;i<n;i++) {
   void *manager=STHChooserCopyManagerAt(i,managers); // +1
   NSString *identifier=nil;
   @try { identifier=CFBridgingRelease(STHSystemCopyModelIdentifier(manager)); }
   @finally { STHChooserReleaseSwift(manager); }
   if(!identifier.length)return nil; // don't silently show possibly pinned apps
   [pinned addObject:[identifier copy]];
  }
  NSMutableSet<NSString *> *seen=[NSMutableSet set];
  NSMutableArray *rows=[NSMutableArray array];
  for(unsigned group=0;group<2;group++) {
   const STApp32 *apps=(const void *)((const unsigned char *)catalogs[group]+32);
   for(size_t i=0;i<counts[group];i++) {
    NSString *identifier=CFBridgingRelease(STHSystemCopySwiftString(apps[i].identifier.word));
    if(!identifier.length || isVirtualAction(identifier) ||
       [pinned containsObject:identifier] || [seen containsObject:identifier])continue;
    NSString *name=CFBridgingRelease(STHSystemCopySwiftString(apps[i].name.word));
    [seen addObject:[identifier copy]];
    [rows addObject:@{@"identifier":[identifier copy],
                     @"name":[(name.length?name:identifier) copy],
                     @"source":group?@"system":@"user"}];
   }
  }
  return [rows copy]; // retains strings, not native buffers or manager pointers
 } @finally {
  STHChooserReleaseArray(managers);
  STHChooserReleaseArray(catalogs[0]);
  STHChooserReleaseArray(catalogs[1]);
 }
}

// YES means submitted to native Void admission, not "a scene definitely opened".
// Current native catalog membership and pin exclusion are rechecked on tap.
BOOL STHChooserSubmitFloating(NSString *identifier) {
 if(![identifier isKindOfClass:NSString.class] || !identifier.length)return NO;
 NSArray *rows=STHChooserSnapshotUnpinned();
 BOOL found=NO;
 for(NSDictionary *row in rows)if([row[@"identifier"] isEqualToString:identifier]){found=YES;break;}
 if(!found)return NO;
 uintptr_t words[2];
 STHSystemMakeSwiftString(identifier,words); // +1 Swift String
 void *model=STHChooserBuildManagerConsumed(words[0],words[1]); // consumes +1
 // NEVER bridgeObjectRelease(words[1]) here; native builder already did it.
 @try { STHChooserOpenModelAnimated(model); }
 @finally { STHChooserReleaseSwift(model); }
 return YES;
}

// A center selection enters the same native selected-App animation and
// admission used by ordinary ring apps. The existing action gate consumes
// this exact ID before any scene/window is created. No saved ring item exists.
BOOL STHChooserSubmitCenterSelection(void){
 if(!NSThread.isMainThread||!STHChooserImageReady())return NO;
 uintptr_t words[2];STHSystemMakeSwiftString(@STH_APP_CHOOSER_ID,words);
 void *model=STHChooserBuildManagerConsumed(words[0],words[1]);
 if(!model)return NO;
 @try{STHChooserOpenModelAnimated(model);}
 @finally{STHChooserReleaseSwift(model);}
 return YES;
}
