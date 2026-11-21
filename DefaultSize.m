#import <Foundation/Foundation.h>
extern void STHNativePresent(void *);
extern void STHNativeInitialSize(void *);
extern BOOL STHNativeMinimized(void *);
extern void STHNativeSetMinimized(void *,BOOL);
#import "ViewportHost.h"
static NSHashTable *initializedModels;
void STHFirstPresentation(void *model) {
 if(!model)return;
 id strong=(__bridge id)model;
 if(!initializedModels)initializedModels=[NSHashTable weakObjectsHashTable];
 BOOL first=![initializedModels containsObject:strong];
 if(first)[initializedModels addObject:strong];
 // The scene and all model fields exist at this point, unlike in init.
 // Reopening a minimized model through an App selection restores full-window state.
 if(STHNativeMinimized(model))STHNativeSetMinimized(model,NO);
 STHNativePresent(model);
 if(first){
  // Call the EXACT same body as bottom-right long-press reset. Do it within
  // the native presentation transaction; do not schedule a second jump/reset.
  STHNativeInitialSize(model);
 }
#if !defined(STH_DEFAULT_SIZE_TEST)
 STHViewportModelChanged(model);
#endif
}
