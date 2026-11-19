#ifndef STH_EDITOR_REFINEMENT_H
#define STH_EDITOR_REFINEMENT_H
#include "EditorAssembly.h"
// Select a compact composer; do not mistake a305pt emotion/page container for
// the entry bar. If no compact candidate exists, skip rather than shift a page.
static inline bool STHCompactComposer(double width,double height,double sw,double sh,bool scrolling){
 return !scrolling&&isfinite(width)&&isfinite(height)&&width>=sw*.78&&height>=20&&
        height<=fmin(200.0,sh*.29);
}
// Gaps between confirmed sibling control rows can be layout spacing. Permit
// only a bounded fraction of row height, not an app-wide fixed compensation.
static inline bool STHRefinedRow(STHRect group,STHRect row,double sh,bool strong,bool sameParent){
 if(!strong||!STHFiniteRect(group)||!STHFiniteRect(row)||sh<=1)return false;
 double x=fmin(group.x+group.w,row.x+row.w)-fmax(group.x,row.x);
 double gap=row.y-(group.y+group.h);
 double tolerance=sameParent?fmin(40.0,fmin(group.h,row.h)*.5):5.0;
 return row.w>=group.w*.60&&x>=group.w*.55&&row.h>=8&&row.h<=fmin(300,sh*.42)&&
        row.y>=group.y&&gap<=tolerance&&row.y+row.h>group.y+group.h+.5&&
        row.y+row.h-group.y<=sh*.66;
}
// Correct from the current measured residual, not an ever-growing reconstructed
// baseline. Parent AutoLayout may relocate the child without changing transform.
static inline double STHRefinedLift(double previous,double visibleBottom,double keyTop,
 double baseTop,double assemblyHeight,double sh){
 if(!isfinite(previous)||!isfinite(visibleBottom)||!isfinite(keyTop)||!isfinite(baseTop)||
    !isfinite(assemblyHeight)||sh<=1||assemblyHeight<=0||assemblyHeight>sh*.66)return previous;
 double residual=visibleBottom-keyTop;
 if(fabs(residual)<=.25)return previous;
 double limit=fmin(fmax(0,baseTop),sh*.50);
 double result=fmin(limit,fmax(0,previous+residual));
 return result;
}
// Only an explicitly detected transparent tail may be collapsed downward. No
// general downward movement of intentionally high editors or whole popups.
static inline double STHTransparentTailDrop(double containerBottom,double controlsBottom,
 double keyTop,double rootHeight,bool transparent,bool stable){
 if(!transparent||!stable||!isfinite(containerBottom)||!isfinite(controlsBottom)||
    !isfinite(keyTop)||rootHeight<=0)return 0;
 double tail=containerBottom-controlsBottom,gap=keyTop-controlsBottom;
 if(tail<1||tail>fmin(44,rootHeight*.35)||gap<1||gap>tail+2)return 0;
 return fmin(tail,gap);
}
#endif
