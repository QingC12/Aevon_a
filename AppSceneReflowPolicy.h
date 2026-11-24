#ifndef APP_SCENE_REFLOW_POLICY_H
#define APP_SCENE_REFLOW_POLICY_H

#include <math.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double width;
    double height;
} STHRSize;

typedef struct {
    bool inject;
    bool settingMaskPresent;
    bool settingBit31;
    bool queryIsMainScreen;
    bool sceneIsOnMainScreen;
    bool hostedLayout;
    bool sceneConnected;
    /* Connected and not backgrounded. A floating card is frequently neither the
     * key scene nor foreground active while it resizes or plays in place, so
     * neither of those may decide the layout size. */
    bool sceneUsable;
    bool sceneBoundsValid;
    bool physicalBoundsValid;
    STHRSize sceneSize;
    STHRSize physicalSize;
} STHRPolicyInput;

static inline bool STHRSizeIsValid(STHRSize size) {
    return isfinite(size.width) && isfinite(size.height) &&
           size.width > 0.0 && size.height > 0.0;
}

/* Treat swapped orientations as the same full-screen physical dimensions. */
static inline bool STHRNearlyEqual(double a, double b) {
    return fabs(a - b) <= 0.5;
}

static inline bool STHRSceneDiffersFromPhysicalScreen(STHRSize scene,
                                                       STHRSize physical) {
    if (!STHRSizeIsValid(scene) || !STHRSizeIsValid(physical)) return false;
    bool same = (STHRNearlyEqual(scene.width, physical.width) &&
                 STHRNearlyEqual(scene.height, physical.height)) ||
                (STHRNearlyEqual(scene.width, physical.height) &&
                 STHRNearlyEqual(scene.height, physical.width));
    return !same;
}

/* No card scale, card frame, or keyboard geometry participates in this policy.
 * The scene must differ from the physical screen, which is exactly what a
 * carded viewport does and what a full-screen application never does. */
static inline bool STHRShouldReflow(const STHRPolicyInput *input) {
    if (!input) return false;
    if (!input->inject || !input->settingMaskPresent || !input->settingBit31)
        return false;
    if (!input->queryIsMainScreen || !input->sceneIsOnMainScreen)
        return false;
    if (!input->hostedLayout || !input->sceneConnected || !input->sceneUsable)
        return false;
    if (!input->sceneBoundsValid || !input->physicalBoundsValid)
        return false;
    return STHRSceneDiffersFromPhysicalScreen(input->sceneSize,
                                               input->physicalSize);
}

#ifdef __cplusplus
}
#endif
#endif
