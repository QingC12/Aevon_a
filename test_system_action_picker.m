#import <Foundation/Foundation.h>
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#import "SystemActionCatalog.h"
typedef struct{uintptr_t name[2],identifier[2];} Record;
extern void *STHSystemActionPrependPicker(void *);
extern BOOL STHSystemActionIsSavedIdentifier(const uintptr_t *);
static BOOL enabled=YES;
BOOL STHSystemActionRuntimeReady(void){return YES;}
BOOL STHSystemActionsEnabled(void){return enabled;}
void STHSystemMakeSwiftString(NSString *value,uintptr_t *words){words[0]=(uintptr_t)CFBridgingRetain(value);words[1]=0x1234;}
void *STHSystemCopySwiftString(const uintptr_t *words){assert(words[1]==0x1234);return (void *)CFRetain((CFTypeRef)words[0]);}
static void releaseArray(void *raw){
 size_t count=((uintptr_t *)raw)[2];Record *records=(void *)((char *)raw+32);
 for(size_t i=0;i<count;i++){CFRelease((CFTypeRef)records[i].name[0]);CFRelease((CFTypeRef)records[i].identifier[0]);}
 free(raw);
}
void *STHSystemGrowApps(uintptr_t unique,uintptr_t capacity,uintptr_t grow,void *owned){
 assert(unique==0&&grow==0);size_t count=((uintptr_t *)owned)[2];assert(capacity>=count);
 void *result=calloc(1,32+capacity*32);memcpy(result,owned,32+count*32);((uintptr_t *)result)[3]=capacity*2;
 Record *records=(void *)((char *)result+32);
 for(size_t i=0;i<count;i++){CFRetain((CFTypeRef)records[i].name[0]);CFRetain((CFTypeRef)records[i].identifier[0]);}
 releaseArray(owned);return result;
}
static void *array(NSArray<NSString *> *ids){
 void *raw=calloc(1,32+ids.count*32);((uintptr_t *)raw)[2]=ids.count;((uintptr_t *)raw)[3]=ids.count*2;
 Record *records=(void *)((char *)raw+32);
 for(NSUInteger i=0;i<ids.count;i++){STHSystemMakeSwiftString([NSString stringWithFormat:@"普通应用%lu",(unsigned long)i],records[i].name);STHSystemMakeSwiftString(ids[i],records[i].identifier);}
 return raw;
}
static NSString *identifier(void *raw,size_t i){return CFBridgingRelease(STHSystemCopySwiftString(((Record *)((char *)raw+32))[i].identifier));}
int main(void){@autoreleasepool{
 void *raw=array(@[@"com.apple.mobilesafari",@"com.tencent.xin",@"com.openminis.app"]);
 raw=STHSystemActionPrependPicker(raw);assert(((uintptr_t *)raw)[2]==5);
 assert([identifier(raw,0) isEqualToString:@STH_SCREENSHOT_ID]);assert([identifier(raw,1) isEqualToString:@STH_SCREEN_RECORDING_ID]);
 Record *items=(void *)((char *)raw+32);
 assert(STHSystemActionIsSavedIdentifier(items[0].identifier));assert(STHSystemActionIsSavedIdentifier(items[1].identifier));
 assert(!STHSystemActionIsSavedIdentifier(items[2].identifier));
 assert([identifier(raw,2) isEqualToString:@"com.apple.mobilesafari"]);assert([identifier(raw,3) isEqualToString:@"com.tencent.xin"]);assert([identifier(raw,4) isEqualToString:@"com.openminis.app"]);
 for(int i=0;i<100;i++){raw=STHSystemActionPrependPicker(raw);assert(((uintptr_t *)raw)[2]==5);}
 releaseArray(raw);
 raw=array(@[]);raw=STHSystemActionPrependPicker(raw);assert(((uintptr_t *)raw)[2]==2);releaseArray(raw);
 raw=array(@[@"com.apple.mobilesafari",@STH_SCREEN_RECORDING_ID]);raw=STHSystemActionPrependPicker(raw);
 assert(((uintptr_t *)raw)[2]==3);assert([identifier(raw,0) isEqualToString:@STH_SCREENSHOT_ID]);assert([identifier(raw,1) isEqualToString:@STH_SCREEN_RECORDING_ID]);releaseArray(raw);
 raw=array(@[@"com.apple.mobilesafari"]);enabled=NO;assert(raw==STHSystemActionPrependPicker(raw));assert(((uintptr_t *)raw)[2]==1);releaseArray(raw);
 NSLog(@"System native picker: ordering, ownership-copy contract, dedup and off-state passed");
}return 0;}
