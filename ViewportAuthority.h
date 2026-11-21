#ifndef STH_VIEWPORT_AUTHORITY_H
#define STH_VIEWPORT_AUTHORITY_H
#include "ViewportGeometry.h"
/* Request geometry is deliberately not an input. A valid-looking app frame
 * cannot create, replace or invalidate SpringBoard's physical keyboard fact. */
static inline bool STHVAuthoritativeFrame(STHVRect card,STHVRect keyboard,
    STHVRect screen,uint64_t generation,bool visible,STHVRect *frame){
 if(!generation||!visible||!STHVValid(card)||!STHVKeyboard(keyboard,screen))return false;
 if(frame)*frame=keyboard;return true;
}
static inline bool STHVAuthoritativeMap(STHVRect card,STHVRect keyboard,
    STHVRect screen,STHVRect scene,uint64_t generation,bool visible,STHVRect *mapped){
 STHVRect physical;
 if(!STHVAuthoritativeFrame(card,keyboard,screen,generation,visible,&physical)||!STHVValid(scene))return false;
 if(mapped)*mapped=STHVMap(card,physical,scene);return true;
}
typedef enum {STHVClientNative,STHVClientPending,STHVClientHidden,STHVClientVisible} STHVClientMode;
static inline STHVClientMode STHVClientAuthorityMode(bool hosted,STHVRect card,STHVRect scene,STHVRect screen,uint64_t generation,bool visible){
 if(!hosted||!STHVValid(card)||!STHVValid(scene)||!STHVValid(screen))return STHVClientNative;
 if(fabs(scene.w-screen.w)<=.5&&fabs(scene.h-screen.h)<=.5)return STHVClientNative;
 if(!generation)return STHVClientPending;
 return visible?STHVClientVisible:STHVClientHidden;
}
#endif
