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
    /* Retained only so the archived 2.0.32 source still builds as a negative
     * control: neither fact gates the answer any more. */
    bool sceneForegroundActive;
    bool sceneHasKeyWindow;
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

/* The card, not the scene, is the viewport the user is looking at.
 *
 * The scene a carded application is hosted in can lag a resize, can be
 * ambiguous while a transition is in flight, and (on this platform) is often
 * only ever updated when the card is first presented. A custom window ratio
 * therefore reaches the scene late or not at all, and an application that lays
 * out from the screen width keeps using the previous ratio: Douyin is the one
 * that shows it, because its action column stays on the old right edge and
 * falls outside a narrower card.
 *
 * The host publishes the card rectangle on every change, in screen points, and
 * the scene is in those same points, so the card is the one number that always
 * describes the viewport. It is accepted only when it is a plausible viewport
 * (a dock thumbnail is not) and when it is still not the physical screen, so a
 * genuinely full-screen presentation keeps returning the native answer. */
static inline bool STHRCardViewport(STHRSize card, STHRSize physical,
                                    STHRSize *out) {
    if (!out || !STHRSizeIsValid(card) || !STHRSizeIsValid(physical))
        return false;
    if (card.width < 80.0 || card.height < 80.0) return false;
    if (card.width > physical.width + 0.5 ||
        card.height > physical.height + 0.5) return false;
    if (!STHRSceneDiffersFromPhysicalScreen(card, physical)) return false;
    out->width = card.width;
    out->height = card.height;
    return true;
}

#ifdef __cplusplus
}
#endif
#endif
