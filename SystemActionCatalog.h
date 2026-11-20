#ifndef STH_SYSTEM_ACTION_CATALOG_H
#define STH_SYSTEM_ACTION_CATALOG_H
#include <string.h>

// Namespaced virtual items, not installed app bundle identifiers. Membership
// is handled by Stheno's original Apps list; no extra enable preference exists.
#define STH_SCREENSHOT_ID "com.nx.stheno.action.screenshot"
#define STH_SCREEN_RECORDING_ID "com.nx.stheno.action.screen-recording"
typedef enum {
 STHSystemActionNone=0,
 STHSystemActionScreenshot=1,
 STHSystemActionScreenRecording=2
} STHSystemAction;
static inline STHSystemAction STHSystemActionForIdentifier(const char *identifier){
 if(!identifier)return STHSystemActionNone;
 if(strcmp(identifier,STH_SCREENSHOT_ID)==0)return STHSystemActionScreenshot;
 if(strcmp(identifier,STH_SCREEN_RECORDING_ID)==0)return STHSystemActionScreenRecording;
 return STHSystemActionNone;
}
// Only for the system picker. NEVER apply this priority to the ring array.
static inline unsigned STHSystemPickerPriority(const char *identifier){
 switch(STHSystemActionForIdentifier(identifier)){
  case STHSystemActionScreenshot:return 0;
  case STHSystemActionScreenRecording:return 1;
  default:return 2;
 }
}
#endif
