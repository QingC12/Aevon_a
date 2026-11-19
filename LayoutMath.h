#ifndef STH_LAYOUT_MATH_H
#define STH_LAYOUT_MATH_H
#include <stdbool.h>
#include <stdint.h>
#include <math.h>
typedef struct { double x,y,w,h; } STHRect;
static inline bool STHFiniteRect(STHRect r) {
 return isfinite(r.x)&&isfinite(r.y)&&isfinite(r.w)&&isfinite(r.h)&&r.w>1&&r.h>1;
}
// Card and keyboard are physical-screen points; app bounds are scene points.
static inline bool STHMapHostedKeyboard(STHRect card,STHRect keyboard,STHRect app,
 STHRect *local,double *overlap) {
 if(!STHFiniteRect(card)||!STHFiniteRect(keyboard)||!STHFiniteRect(app)||
    card.w<40||card.h<40||card.w/app.w<.08||card.w/app.w>4||
    card.h/app.h<.08||card.h/app.h>4)return false;
 double sx=card.w/app.w,sy=card.h/app.h;
 STHRect out={app.x+(keyboard.x-card.x)/sx,app.y+(keyboard.y-card.y)/sy,
              keyboard.w/sx,keyboard.h/sy};
 double bottom=app.y+app.h;
 bool horizontal=out.x+out.w>app.x&&out.x<app.x+app.w;
 // A docked keyboard defines a bottom exclusion starting at its TOP. Include
 // any part of the card extending beyond the physical display's bottom too.
 double lift=horizontal?fmax(0,bottom-out.y):0;
 if(horizontal)out.h=fmax(out.h,bottom-out.y);
 // Unlike a generic screen heuristic, a card below keyboard can be fully hidden.
 if(!isfinite(lift))return false;
 *local=out;*overlap=fmin(app.h,lift);return true;
}
// Notification consumers may use either endFrame.origin.y OR endFrame.height.
// Make these equivalent: expose the bottom occlusion, not the full remote keys
// extending below the floating scene. Non-overlap becomes zero-height offscene.
static inline STHRect STHOcclusionFrame(STHRect scene,STHRect mapped) {
 double inset=fmin(scene.h,fmax(0,scene.y+scene.h-mapped.y));
 if(mapped.x+mapped.w<=scene.x||mapped.x>=scene.x+scene.w)inset=0;
 return (STHRect){scene.x,scene.y+scene.h-inset,scene.w,inset};
}
// Signed 1/8pt rectangle in one notify state: no files, text or credentials.
static inline bool STHPackRect(STHRect r,uint64_t *out) {
 if(!STHFiniteRect(r))return false;
 double v[4]={r.x,r.y,r.w,r.h};uint64_t bits=0;
 for(int i=0;i<4;i++){
  double n=round(v[i]*8);if(n<INT16_MIN||n>INT16_MAX)return false;
  bits|=((uint64_t)(uint16_t)(int16_t)n)<<(i*16);
 }
 *out=bits;return true;
}
static inline STHRect STHUnpackRect(uint64_t bits) {
 STHRect r={(int16_t)bits/8.0,(int16_t)(bits>>16)/8.0,
            (int16_t)(bits>>32)/8.0,(int16_t)(bits>>48)/8.0};return r;
}
#endif
