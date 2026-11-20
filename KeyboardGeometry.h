#ifndef STH_KEYBOARD_GEOMETRY_H
#define STH_KEYBOARD_GEOMETRY_H
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>

static inline double STHKeyboardScaleFactor(double currentScale,double cardWidth,double viewportWidth){
 if(!isfinite(currentScale)||!isfinite(cardWidth)||!isfinite(viewportWidth)||
    currentScale<=0||cardWidth<=1||viewportWidth<=1)return 1.0;
 return viewportWidth/cardWidth;
}

static inline double STHKeyboardVisibleDelta(double cardTop,double cardHeight,double factor,
 double screenTop,double keyboardTop){
 if(!isfinite(cardTop)||!isfinite(cardHeight)||!isfinite(factor)||!isfinite(screenTop)||
    !isfinite(keyboardTop)||cardHeight<=1||factor<=0||keyboardTop<=screenTop)return 0;
 double height=cardHeight*factor;
 double top=cardTop+(cardHeight-height)*.5;
 double room=fmin(120.0,height*.25);
 double limit=fmax(screenTop,keyboardTop-room);
 return top>limit?limit-top:0;
}
#endif
