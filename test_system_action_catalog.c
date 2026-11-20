#include <assert.h>
#include <stddef.h>
#include "SystemActionCatalog.h"
int main(void){
 assert(STHSystemActionForIdentifier(NULL)==STHSystemActionNone);
 assert(STHSystemActionForIdentifier("")==STHSystemActionNone);
 assert(STHSystemActionForIdentifier(STH_SCREENSHOT_ID)==STHSystemActionScreenshot);
 assert(STHSystemActionForIdentifier(STH_SCREEN_RECORDING_ID)==STHSystemActionScreenRecording);
 const char *ordinary[]={"com.apple.mobilesafari","com.apple.ScreenRecording","com.apple.ScreenshotServicesService","com.tencent.xin","com.nx.stheno.action.screenshot.backup","com.nx.stheno.action.screen-recording.fake"};
 for(size_t i=0;i<sizeof(ordinary)/sizeof(*ordinary);i++){
  assert(STHSystemActionForIdentifier(ordinary[i])==STHSystemActionNone);
  assert(STHSystemPickerPriority(ordinary[i])==2);
 }
 assert(STHSystemPickerPriority(STH_SCREENSHOT_ID)==0);
 assert(STHSystemPickerPriority(STH_SCREEN_RECORDING_ID)==1);
 return 0;
}
