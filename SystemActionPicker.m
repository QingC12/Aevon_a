#import <Foundation/Foundation.h>
#import "SystemActionCatalog.h"
#import "SystemActionOrder.h"
extern BOOL STHSystemActionRuntimeReady(void);
extern BOOL STHSystemActionsEnabled(void);
extern void *STHSystemCopySwiftString(const uintptr_t *words);
extern void STHSystemMakeSwiftString(NSString *value,uintptr_t *words);
extern void *STHSystemGrowApps(uintptr_t unique,uintptr_t capacity,uintptr_t grow,void *owned);

typedef struct{uintptr_t name[2],identifier[2];} STHNativeAppRecord;
_Static_assert(sizeof(STHNativeAppRecord)==32,"Pinned native App layout changed");
static unsigned priority(const void *record,void *unused){
 (void)unused;
 NSString *identifier=CFBridgingRelease(STHSystemCopySwiftString((const uintptr_t *)record+2));
 return STHSystemPickerPriority(identifier.UTF8String);
}
// Exact virtual IDs are valid saved items even though SpringBoard has no
// installed SBApplication object for them. Ordinary app validity is unchanged.
BOOL STHSystemActionIsSavedIdentifier(const uintptr_t *words){
 if(!words||!STHSystemActionRuntimeReady())return NO;
 NSString *identifier=CFBridgingRelease(STHSystemCopySwiftString(words));
 return STHSystemActionForIdentifier(identifier.UTF8String)!=STHSystemActionNone;
}
// Consumes/returns one owned native Array<App> reference. Called only at the
// successful System publication load, AFTER ALL native sorting. Native grow
// with unique=0 copies/retains real App records using the ORIGINAL metadata;
// it also releases the consumed source. No fake Swift type or LS proxy exists.
void *STHSystemActionPrependPicker(void *owned){
 if(!owned||!STHSystemActionsEnabled()||!STHSystemActionRuntimeReady())return owned;
 uintptr_t *header=owned;size_t count=header[2];if(count>65536)return owned;
 BOOL present[2]={NO,NO};
 STHNativeAppRecord *old=(void *)((unsigned char *)owned+32);
 for(size_t i=0;i<count;i++){
  unsigned rank=priority(&old[i],NULL);if(rank<2)present[rank]=YES;
 }
 STHNativeAppRecord added[2]={0};size_t missing=0;
 if(!present[0]){
  STHSystemMakeSwiftString(@"截图",added[missing].name);
  STHSystemMakeSwiftString(@STH_SCREENSHOT_ID,added[missing].identifier);missing++;
 }
 if(!present[1]){
  STHSystemMakeSwiftString(@"录屏",added[missing].name);
  STHSystemMakeSwiftString(@STH_SCREEN_RECORDING_ID,added[missing].identifier);missing++;
 }
 void *result=STHSystemGrowApps(0,count+missing,0,owned);
 STHNativeAppRecord *records=(void *)((unsigned char *)result+32);
 memmove(records+missing,records,count*sizeof(*records));
 memcpy(records,added,missing*sizeof(*records));
 ((uintptr_t *)result)[2]=count+missing;
 STHSystemStableFront(records,count+missing,32,priority,NULL);
 return result;
}
