#ifndef STH_KEYBOARD_PLANE_MATH_H
#define STH_KEYBOARD_PLANE_MATH_H
#include "LayoutMath.h"
// Confidence is structural:3 keyplane,2 dedicated keyboard layout,0 broad
// host/impl/accessory wrapper. Broad hosts cannot override a valid native frame.
static inline bool STHSelectKeyboardPlane(STHRect candidate,int confidence,STHRect host,
 STHRect screen,int previousConfidence,STHRect previous){
 if(confidence<2||!STHFiniteRect(candidate)||!STHFiniteRect(host)||!STHFiniteRect(screen)||
    candidate.w<screen.w*.7||candidate.h<60||candidate.h>screen.h*.7||
    fabs(candidate.y+candidate.h-screen.y-screen.h)>6)return false;
 if(confidence>previousConfidence)return true;
 // Same-specificity nested nodes: the lower/smaller true keyplane is preferred
 // over its enclosing layout, not a union that drags in app accessory content.
 return confidence==previousConfidence&&candidate.h<previous.h-.5;
}
static inline bool STHKeyboardConnectedRow(STHRect keys,STHRect row,STHRect screen,
 bool specificSystemRole,bool wrapsApp){
 return specificSystemRole&&!wrapsApp&&STHFiniteRect(row)&&
  row.w>=screen.w*.7&&row.h>=8&&row.h<=160&&row.y>=screen.y&&
  row.y<keys.y&&fabs(row.y+row.h-keys.y)<=4;
}
#endif
