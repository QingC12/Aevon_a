#ifndef STH_VIEWPORT_GEOMETRY_H
#define STH_VIEWPORT_GEOMETRY_H

#include <stdint.h>
#include <stdbool.h>
#include <math.h>

typedef struct STHVRect { double x, y, w, h; } STHVRect;

static inline bool STHVFinite(STHVRect r)
{
    return isfinite(r.x) && isfinite(r.y) && isfinite(r.w) && isfinite(r.h);
}

static inline bool STHVValid(STHVRect r)
{
    return STHVFinite(r) && r.w > 0.0 && r.h > 0.0 &&
           isfinite(r.x + r.w) && isfinite(r.y + r.h);
}

/* Empty occlusion rectangles are comparable even though they are not valid. */
static inline bool STHVNear(STHVRect a, STHVRect b, double tolerance)
{
    return STHVFinite(a) && STHVFinite(b) && isfinite(tolerance) &&
           tolerance >= 0.0 && fabs(a.x - b.x) <= tolerance &&
           fabs(a.y - b.y) <= tolerance && fabs(a.w - b.w) <= tolerance &&
           fabs(a.h - b.h) <= tolerance;
}

/* All arguments use the same physical screen coordinate system. */
static inline bool STHVKeyboard(STHVRect r, STHVRect screen)
{
    return STHVValid(r) && STHVValid(screen) && r.w >= 0.7 * screen.w &&
           r.h >= 60.0 && r.h <= 0.75 * screen.h &&
           fabs((r.y + r.h) - (screen.y + screen.h)) <= 20.0 &&
           r.y >= screen.y && r.y < screen.y + screen.h;
}

/* Invalid card/screen returns zero. An invalid keyboard adds no constraint.
 * Callers can use STHVKeyboard to filter hardware/floating keyboards first.
 * The keyboard is a read-only physical rectangle, never a scale target. */
static inline STHVRect STHVTarget(STHVRect card, STHVRect screen,
                                  STHVRect keyboard)
{
    if (!STHVValid(card) || !STHVValid(screen)) return (STHVRect){0};
    double factor = fmin(screen.w / card.w, screen.h / card.h);
    double height = card.h * factor, width = card.w * factor;
    if (!isfinite(factor) || !isfinite(height) || height <= 0.0)
        return (STHVRect){0};
    /* Keep the complete remote scene on-screen. Otherwise a docked keyboard
     * may end above the card bottom, falsely looking like floating occlusion. */
    double y = fmin(screen.y + screen.h - height,
                    fmax(screen.y, card.y + card.h * 0.5 - height * 0.5));
    double room = fmin(120.0, height * 0.25);
    if (STHVValid(keyboard) && y > keyboard.y - room)
        y = fmax(screen.y, keyboard.y - room);
    STHVRect result = {screen.x + (screen.w - width) * 0.5, y, width, height};
    return STHVValid(result) ? result : (STHVRect){0};
}

/* Map only the physical intersection, exactly once, from card to scene.
 * X and Y have independent affine scales; partial widths stay partial.
 * Non-bottom intersections remain floating and therefore yield zero inset. */
static inline STHVRect STHVMap(STHVRect card, STHVRect physical,
                               STHVRect sceneBounds)
{
    STHVRect empty = STHVValid(sceneBounds)
        ? (STHVRect){sceneBounds.x, sceneBounds.y + sceneBounds.h,
                     sceneBounds.w, 0.0} : (STHVRect){0};
    if (!STHVValid(card) || !STHVValid(physical) || !STHVValid(sceneBounds))
        return empty;
    double left = fmax(card.x, physical.x);
    double right = fmin(card.x + card.w, physical.x + physical.w);
    double top = fmax(card.y, physical.y);
    double bottom = fmin(card.y + card.h, physical.y + physical.h);
    if (right <= left || bottom <= top) return empty;
    left = fmax(sceneBounds.x, sceneBounds.x +
                ((left - card.x) / card.w) * sceneBounds.w);
    right = fmin(sceneBounds.x + sceneBounds.w, sceneBounds.x +
                 ((right - card.x) / card.w) * sceneBounds.w);
    top = fmax(sceneBounds.y, sceneBounds.y +
               ((top - card.y) / card.h) * sceneBounds.h);
    bottom = fmin(sceneBounds.y + sceneBounds.h, sceneBounds.y +
                  ((bottom - card.y) / card.h) * sceneBounds.h);
    if (right <= left || bottom <= top) return empty;
    return (STHVRect){left, top, right - left, bottom - top};
}

/* A positive horizontal overlap and contact with the scene bottom are needed.
 * One ULP at the bottom permits arithmetic round-off, not UI padding. */
static inline double STHVInset(STHVRect mapped, STHVRect sceneBounds)
{
    if (!STHVValid(mapped) || !STHVValid(sceneBounds)) return 0.0;
    double bottom = sceneBounds.y + sceneBounds.h;
    if (fmin(mapped.x + mapped.w, sceneBounds.x + sceneBounds.w) <=
        fmax(mapped.x, sceneBounds.x) ||
        mapped.y + mapped.h < nextafter(bottom, -INFINITY)) return 0.0;
    return fmin(sceneBounds.h, fmax(0.0, bottom - mapped.y));
}

/* notify64 layout, low to high: x, y, w, h; each is 16 quarter-point bits.
 * X/Y use a 4096-point bias. Round to nearest quarter point, ties upward.
 * Check the original range before rounding; never saturate or wrap.
 * Zero sizes are encodable. Failure clears the payload, if non-null. */
static inline bool STHVPackRect(STHVRect r, uint64_t *payload)
{
    if (!payload) return false;
    *payload = 0;
    if (!STHVFinite(r) || r.x < -4096.0 || r.x > 12287.75 ||
        r.y < -4096.0 || r.y > 12287.75 ||
        r.w < 0.0 || r.w > 16383.75 || r.h < 0.0 || r.h > 16383.75)
        return false;
    uint64_t x = (uint64_t)round((r.x + 4096.0) * 4.0);
    uint64_t y = (uint64_t)round((r.y + 4096.0) * 4.0);
    uint64_t w = (uint64_t)round(r.w * 4.0);
    uint64_t h = (uint64_t)round(r.h * 4.0);
    *payload = x | (y << 16) | (w << 32) | (h << 48);
    return true;
}

/* Every 64-bit payload decodes; geometry validation is a separate step. */
static inline STHVRect STHVUnpackRect(uint64_t payload)
{
    return (STHVRect){
        (double)(payload & UINT64_C(0xffff)) * 0.25 - 4096.0,
        (double)((payload >> 16) & UINT64_C(0xffff)) * 0.25 - 4096.0,
        (double)((payload >> 32) & UINT64_C(0xffff)) * 0.25,
        (double)((payload >> 48) & UINT64_C(0xffff)) * 0.25
    };
}

#endif
