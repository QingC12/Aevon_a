#ifndef STH_DOCK_ORIENTATION_H
#define STH_DOCK_ORIENTATION_H
#include <stdbool.h>
#include <math.h>
static inline bool STHDockUsesNativeReflow(unsigned orientation){return orientation!=3&&orientation!=4;}
static inline unsigned STHDockSideBit(double offsetX){return offsetX<0?1u:2u;}
static inline bool STHDockMayApply(unsigned blockedSides,double offsetX,unsigned orientation){
 return STHDockUsesNativeReflow(orientation)&&(blockedSides&STHDockSideBit(offsetX))==0;
}
#endif
