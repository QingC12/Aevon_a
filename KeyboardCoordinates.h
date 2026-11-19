#ifndef STH_KEYBOARD_COORDINATES_H
#define STH_KEYBOARD_COORDINATES_H
#include <math.h>
#include <stdbool.h>

// All inputs must already be in the SAME app-window coordinate space.
static inline bool STHLocalKeyboardOverlap(double left,double top,double width,double height,
 double x,double y,double w,double h,bool ignoreX,double *out) {
 if(!isfinite(left)||!isfinite(top)||!isfinite(width)||!isfinite(height)||
    !isfinite(x)||!isfinite(y)||!isfinite(w)||!isfinite(h)||width<=1||height<=1||w<=1||h<=1)
  return false;
 if(y+h<top+height-2) return false; // floating keyboard: no bottom obstruction
 if(!ignoreX&&(x+w<=left||x>=left+width)){*out=0;return true;}
 double overlap=fmax(0,fmin(top+height,y+h)-fmax(top,y));
 // Full-screen keyboard CONTAINERS are not actual keyboard frames.
 if(overlap>height*.70) return false;
 *out=overlap;return true;
}
static inline bool STHPhysicalFrame(double x,double y,double w,double h,double screenWidth,double screenHeight) {
 return isfinite(x)&&isfinite(y)&&isfinite(w)&&isfinite(h)&&isfinite(screenWidth)&&isfinite(screenHeight)
  &&screenWidth>1&&screenHeight>1&&w>=screenWidth*.70&&h>=60&&h<screenHeight*.70
  &&fabs(y+h-screenHeight)<=6&&y>=0;
}
#endif
