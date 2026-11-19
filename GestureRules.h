#ifndef STH_GESTURE_RULES_H
#define STH_GESTURE_RULES_H

#include <math.h>
#include <stdbool.h>

typedef enum {
    STHYellowPending,
    STHYellowMoving,
    STHYellowCloseArmed
} STHYellowMode;

static inline STHYellowMode STHYellowNext(STHYellowMode mode,
    double elapsed, double previousDistance, double distance)
{
    if (mode != STHYellowPending) return mode;
    if (elapsed >= 0.25 && previousDistance <= 3.0) return STHYellowCloseArmed;
    if (distance > 3.0) return STHYellowMoving;
    return STHYellowPending;
}

static inline bool STHYellowCloses(STHYellowMode mode, double dx, double dy)
{
    return mode == STHYellowCloseArmed && -dy >= 24.0 && -dy > fabs(dx);
}

#endif
