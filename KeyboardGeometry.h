#ifndef STH_KEYBOARD_GEOMETRY_H
#define STH_KEYBOARD_GEOMETRY_H
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>

static inline double STHKeyboardScaleFactor(double currentScale, double cardWidth,
    double viewportWidth) {
    if (!isfinite(currentScale) || !isfinite(cardWidth) ||
        !isfinite(viewportWidth) || currentScale <= 0 || cardWidth <= 1 ||
        viewportWidth <= 1) return 1.0;
    // Full screen width, without the old 12pt margin or 35% enlargement cap.
    return viewportWidth / cardWidth;
}

static inline double STHKeyboardCenterDelta(double cardLeft, double cardWidth,
    double viewportLeft, double viewportWidth, double targetWidth) {
    if (!isfinite(cardLeft) || !isfinite(cardWidth) ||
        !isfinite(viewportLeft) || !isfinite(viewportWidth) ||
        !isfinite(targetWidth) || viewportWidth <= 1 || targetWidth <= 1)
        return 0.0;
    double targetLeft = cardLeft + (cardWidth - targetWidth) * .5;
    double minLeft = viewportLeft;
    double maxLeft = viewportLeft + viewportWidth - targetWidth;
    if (targetLeft < minLeft) targetLeft = minLeft;
    if (targetLeft > maxLeft) targetLeft = maxLeft;
    return targetLeft - cardLeft;
}
#endif
