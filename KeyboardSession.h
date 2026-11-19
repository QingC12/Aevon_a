#ifndef STH_KEYBOARD_SESSION_H
#define STH_KEYBOARD_SESSION_H
#include <stdbool.h>
#include "LayoutMath.h"

// Real physical-screen frames and delivered scene frames have separate storage.
typedef struct {
 bool visible;
 bool hasSceneFrame;
 bool hasPhysicalFrame;
 double physicalAt;
 STHRect sceneFrame;
 STHRect physicalFrame;
} STHKeyboardSession;
static inline void STHSessionHide(STHKeyboardSession *s) {
 s->visible=false;s->hasSceneFrame=false;s->hasPhysicalFrame=false;s->physicalAt=0;
}
static inline void STHSessionPhysical(STHKeyboardSession *s,STHRect r,double now,bool synthetic,bool valid) {
 if(synthetic||!valid)return;
 s->physicalFrame=r;s->physicalAt=now;s->hasPhysicalFrame=true;
}
static inline bool STHSessionNeedsDelivery(STHKeyboardSession *s,STHRect r) {
 if(!s->visible)return false;
 if(!s->hasSceneFrame)return true;
 STHRect p=s->sceneFrame;
 return fabs(p.x-r.x)>.5||fabs(p.y-r.y)>.5||fabs(p.w-r.w)>.5||fabs(p.h-r.h)>.5;
}
static inline void STHSessionCommit(STHKeyboardSession *s,STHRect r) {
 s->sceneFrame=r;s->hasSceneFrame=true;
}
#endif
