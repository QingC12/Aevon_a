#ifndef STH_CHOOSER_MOTION_H
#define STH_CHOOSER_MOTION_H
#include <math.h>
#include <stdbool.h>
typedef struct {double x,v;} STHChooserSpring;
static inline double STHChooserDiameter(double radius,double iconWidth){
 if(!isfinite(radius)||!isfinite(iconWidth)||radius<=0||iconWidth<=0)return 0;
 double freeDiameter=2*radius-iconWidth-4;
 return freeDiameter>=20?fmin(iconWidth,freeDiameter):0;
}
static inline double STHChooserAlpha(double scale){return fmax(0,fmin(1,2*scale-1));}
static inline double STHChooserSpringStep(STHChooserSpring *state,double target,double elapsed,double damping){
 if(!state||!isfinite(target)||!isfinite(elapsed)||elapsed<=0)return state?state->x:0;
 damping=fmax(.35,fmin(1.5,damping));elapsed=fmin(elapsed,.10);
 double response=.30/damping,omega=6.283185307179586/response;
 int steps=(int)ceil(elapsed/.004);double h=elapsed/steps;
 for(int i=0;i<steps;i++){state->v+=(-omega*omega*(state->x-target)-2*damping*omega*state->v)*h;state->x+=state->v*h;}
 if(fabs(state->x-target)<.0001&&fabs(state->v)<.001){state->x=target;state->v=0;}
 return state->x;
}
#endif
