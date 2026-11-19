#import <Foundation/Foundation.h>
#import "EditorProfiles.h"
extern void STHEditorVisibilityLegacyEvent(BOOL);
extern void STHEditorVisibilityRefinedEvent(BOOL);
BOOL STHRefinementEnabled(void){
 static BOOL enabled;static dispatch_once_t once;
 dispatch_once(&once,^{
  NSString *b=NSBundle.mainBundle.bundleIdentifier;
  enabled=STHProfileForBundle(b.UTF8String)!=STHEditorCompatible;
 });return enabled;
}
void STHEditorVisibilityEvent(BOOL showing){
 if(STHRefinementEnabled())STHEditorVisibilityRefinedEvent(showing);
 else STHEditorVisibilityLegacyEvent(showing);
}
