#ifndef STH_DOCK_ORIENTATION_H
#define STH_DOCK_ORIENTATION_H
#include <stdbool.h>
static inline bool STHDockUsesNativeReflow(unsigned orientation){return orientation!=3&&orientation!=4;}
#endif
