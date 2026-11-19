#ifndef STH_KEYBOARD_INSET_MATH_H
#define STH_KEYBOARD_INSET_MATH_H
#include <math.h>
#include <stdbool.h>
// Only reduce an inflated legacy inset, never invent keyboard overlap.
static inline double STHReduceKeyboardInset(double legacy,double left,double top,
 double width,double height,double kleft,double ktop,double kwidth,double kheight,
 bool ignoreHorizontal) {
 if (!isfinite(legacy)||legacy<=0||!isfinite(left)||!isfinite(top)||
     !isfinite(width)||!isfinite(height)||!isfinite(kleft)||!isfinite(ktop)||
     !isfinite(kwidth)||!isfinite(kheight)||width<=0||height<=0||kwidth<=0||kheight<=0)
  return legacy;
 double bottom=top+height;
 if (ktop<=top||ktop>=bottom||ktop+kheight<bottom-2) return legacy;
 if (!ignoreHorizontal && (kleft+kwidth<=left||kleft>=left+width))return legacy;
 double overlap=fmin(height,bottom-ktop);
 return overlap>=1 && overlap+2<legacy ? overlap:legacy;
}
#endif
