#ifndef STH_SCENE_INTERCEPT_POLICY_H
#define STH_SCENE_INTERCEPT_POLICY_H

#include <stdbool.h>
#include <math.h>

/* The scene frame is the only value this module writes, and it is derived from
 * the card the host published. The functions here are pure so the mapping can be
 * proved without a scene, a run loop or a private framework. */
typedef struct STHSIRect { double x, y, w, h; } STHSIRect;

static inline bool STHSIRectValid(STHSIRect r)
{
    return isfinite(r.x) && isfinite(r.y) && isfinite(r.w) && isfinite(r.h) &&
           isfinite(r.x + r.w) && isfinite(r.y + r.h) && r.w > 0.0 && r.h > 0.0;
}

/* A card that covers the screen is not a card: the application keeps its own
 * rectangle and nothing is written into its scene. */
static inline bool STHSICardIsScreen(STHSIRect card, STHSIRect screen)
{
    return STHSIRectValid(card) && STHSIRectValid(screen) &&
           card.w >= screen.w - 1.0 && card.h >= screen.h - 1.0;
}

/* The rectangle the application had is mapped by the ratio between the card and
 * the screen, so a full screen scene becomes exactly the card and a scene that is
 * already inset keeps its own inset relative to the new viewport. The input is
 * the frame the application had BEFORE the first write, never the frame it
 * carries now, so a second pass computes the same target and changes nothing. */
static inline bool STHSIMapTarget(STHSIRect card, STHSIRect screen,
                                  STHSIRect current, STHSIRect *out)
{
    if (!STHSIRectValid(card) || !STHSIRectValid(screen) || !STHSIRectValid(current))
        return false;
    if (screen.w < 80.0 || screen.h < 80.0) return false;
    double sx = card.w / screen.w, sy = card.h / screen.h;
    if (!isfinite(sx) || !isfinite(sy) || sx <= 0.0 || sy <= 0.0) return false;
    STHSIRect target;
    target.x = card.x + (current.x - screen.x) * sx;
    target.y = card.y + (current.y - screen.y) * sy;
    target.w = current.w * sx;
    target.h = current.h * sy;
    if (!STHSIRectValid(target) || target.w < 80.0 || target.h < 80.0) return false;
    if (out) *out = target;
    return true;
}

static inline bool STHSISameRect(STHSIRect a, STHSIRect b)
{
    return fabs(a.x - b.x) < 0.5 && fabs(a.y - b.y) < 0.5 &&
           fabs(a.w - b.w) < 0.5 && fabs(a.h - b.h) < 0.5;
}

#endif
