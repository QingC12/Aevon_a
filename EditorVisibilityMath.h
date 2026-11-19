#ifndef STH_EDITOR_VISIBILITY_MATH_H
#define STH_EDITOR_VISIBILITY_MATH_H
#include <math.h>
// Keep the entire measured composer assembly above the measured keyboard top.
// A high/already-visible bar is left alone; no universal45/72pt padding.
static inline double STHComposerLift(double top,double bottom,double keyboardTop,double sceneHeight){
 if(!isfinite(top)||!isfinite(bottom)||!isfinite(keyboardTop)||!isfinite(sceneHeight)||
    top<0||bottom<=top||sceneHeight<=1||bottom-top>sceneHeight*.45||keyboardTop<=0)return 0;
 double hidden=bottom-keyboardTop;
 if(hidden<=.75||hidden>sceneHeight*.40)return 0;
 return fmin(hidden,fmax(0,top));
}
#endif
