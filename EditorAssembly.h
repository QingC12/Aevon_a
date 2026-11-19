#ifndef STH_EDITOR_ASSEMBLY_H
#define STH_EDITOR_ASSEMBLY_H
#include "LayoutMath.h"
#include "EditorVisibilityMath.h"
// Strict contiguous full-width row, inside a bounded parent near the actual
// editable responder. May be a private class with no "toolbar" in its name.
static inline bool STHEditorAttachedRow(STHRect root,STHRect row,double sceneHeight,bool controlEvidence){
 if(!STHFiniteRect(root)||!STHFiniteRect(row)||!isfinite(sceneHeight)||sceneHeight<=1)return false;
 double minHeight=controlEvidence?8:18;
 double maxHeight=controlEvidence?fmin(240,sceneHeight*.34):100;
 double horizontal=fmin(root.x+root.w,row.x+row.w)-fmax(root.x,row.x);
 return row.h>=minHeight&&row.h<=maxHeight&&row.w>=root.w*.65&&horizontal>=root.w*.55&&
        row.y>=root.y-2&&row.y<=root.y+root.h+5&&row.y+row.h>root.y+root.h+.5&&
        row.y+row.h-root.y<=sceneHeight*.52;
}
static inline bool STHEditorContainer(double width,double height,double sceneWidth,double sceneHeight,bool scrolling){
 return !scrolling&&isfinite(width)&&isfinite(height)&&width>=sceneWidth*.55&&height>=20&&
        height<=fmin(320,sceneHeight*.46);
}
#endif
