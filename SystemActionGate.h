#ifndef STH_SYSTEM_ACTION_GATE_H
#define STH_SYSTEM_ACTION_GATE_H
#include <stdbool.h>
#include <math.h>
#include <stdint.h>
// Main-thread-only gate. Duplicate gesture/presentation callbacks must not
// capture twice or immediately start-and-stop a recording from one tap.
typedef struct {bool busy,hasPrevious;double lastTap;uint64_t generation;} STHSystemActionGate;
static inline bool STHSystemActionBegin(STHSystemActionGate *gate,double now){
 if(!gate||!isfinite(now)||gate->busy)return false;
 if(gate->hasPrevious&&now-gate->lastTap<.70)return false;
 gate->busy=true;gate->hasPrevious=true;gate->lastTap=now;gate->generation++;return true;
}
static inline bool STHSystemActionFinish(STHSystemActionGate *gate,uint64_t generation){
 if(!gate||generation!=gate->generation||!gate->busy)return false;
 gate->busy=false;return true;
}
#endif
