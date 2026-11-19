#ifndef STH_EDITOR_COMPOSITE_MATH_H
#define STH_EDITOR_COMPOSITE_MATH_H
#include "EditorRefinement.h"
// A20pt text leaf is not the composer. Prefer a bounded owner containing it
// and painted/interactive controls, then include adjacent app rows separately.
static inline bool STHComposerOwner(double width,double height,double sw,double sh,bool scrolling,bool textLeaf){
 return !scrolling&&!textLeaf&&isfinite(width)&&isfinite(height)&&sw>1&&sh>1&&
        width>=sw*.72&&height>=32&&height<=fmin(240,sh*.34);
}
static inline bool STHExpandOwner(STHRect small,STHRect parent,STHRect field,double sh,
 double controlsBottom,unsigned peerControls){
 if(!STHFiniteRect(parent)||!STHFiniteRect(small)||!STHFiniteRect(field)||peerControls<1||
    parent.h>fmin(240,sh*.34)||parent.w<small.w*.96||parent.h<small.h)return false;
 // Expansion must account for controls below the field, not merely add a
 // padded/page wrapper around an unchanged internal text rectangle.
 return controlsBottom>fmax(field.y+field.h,small.y+small.h)+3&&
        controlsBottom<=parent.y+parent.h+3;
}
static inline bool STHCompositeRow(STHRect group,STHRect row,STHRect field,double sh,
 bool related,unsigned controls,bool namedPanel){
 if(!related||(!namedPanel&&controls<2)||!STHFiniteRect(group)||!STHFiniteRect(row)||!STHFiniteRect(field)||sh<=1)return false;
 double cross=fmin(group.x+group.w,row.x+row.w)-fmax(group.x,row.x);
 double gap=row.y-group.y-group.h;
 double spacing=fmin(48,fmin(fmax(group.h,32),fmax(row.h,32))*.75);
 return row.w>=group.w*.58&&cross>=group.w*.5&&row.h>=8&&row.h<=fmin(260,sh*.37)&&
        row.y>=field.y+fmin(field.h*.35,16)-2&&gap<=spacing&&
        row.y+row.h>group.y+group.h+.5&&row.y+row.h-group.y<=sh*.65;
}
// If a private layout repeatedly counteracts our transform, do not grow it
// unbounded. Preserve the smallest effective correction, reset on true targets.
typedef struct{bool valid;double before,after,keys,requested,bestEffective,referenceBottom;unsigned counteractions;} STHResidualHistory;
static inline double STHBoundedResidual(STHResidualHistory *s,double desired,double before,double keys,double nowLift){
 bool same=s->valid&&fabs(keys-s->keys)<=.5;
 bool newGeometry=same&&before>s->referenceBottom+.75;
 if(!same||newGeometry){s->counteractions=0;s->bestEffective=0;s->referenceBottom=before;}
 if(same&&!newGeometry&&fabs(s->after-keys)<=.75&&s->requested>.25){
  if(s->bestEffective<=0||s->requested<s->bestEffective)s->bestEffective=s->requested;
 }
 // Keep evidence of a successful correction across an alternating aligned
 // and counteracted pass.2.0.13 reset the counter on every aligned pass.
 if(same&&!newGeometry&&s->bestEffective>.25&&desired>s->bestEffective+.75&&nowLift>.25){
  s->counteractions++;desired=fmin(desired,s->bestEffective);
 }
 s->valid=true;s->before=before;s->keys=keys;s->requested=desired;return desired;
}
static inline bool STHCanReleaseComposerClip(double height,double sceneHeight,bool isWindow,bool customMask){
 return !isWindow&&!customMask&&isfinite(height)&&isfinite(sceneHeight)&&height>1&&sceneHeight>1&&
        height<=fmin(260,sceneHeight*.40);
}
#endif
