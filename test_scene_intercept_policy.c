/* The pure half of the scene interception: the rectangle a carded application's
 * scene must carry, and the rectangle it must be put back on. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "SceneInterceptPolicy.h"

static STHSIRect screen(void) { return (STHSIRect){0, 0, 430, 932}; }

int main(void) {
    STHSIRect card = {0, 100.5, 430, 731}, out = {0};
    /* A full screen application becomes exactly the card. */
    assert(STHSIMapTarget(card, screen(), screen(), &out));
    assert(STHSISameRect(out, card));
    /* A card is not a card when it is the screen. */
    assert(STHSICardIsScreen(screen(), screen()));
    assert(!STHSICardIsScreen(card, screen()));
    /* A scene that is already inset keeps its own inset relative to the new
     * viewport instead of being stretched to it. */
    STHSIRect inset = {0, 0, 215, 466}, mapped = {0};
    assert(STHSIMapTarget(card, screen(), inset, &mapped));
    assert(out.w > 0 && mapped.w > 0);
    assert(fabs(mapped.w - 215.0) < 0.001 && fabs(mapped.h - 365.5) < 0.001);
    assert(fabs(mapped.x - card.x) < 0.001 && fabs(mapped.y - card.y) < 0.001);
    /* The same card and the same original always produce the same target, so a
     * second pass over an already rewritten scene writes nothing. */
    STHSIRect again = {0};
    assert(STHSIMapTarget(card, screen(), screen(), &again));
    assert(STHSISameRect(out, again));
    /* A card that is not a rectangle, or a screen too small to be one, is not a
     * target. A degenerate result is refused rather than written. */
    assert(!STHSIMapTarget((STHSIRect){0, 0, 0, 0}, screen(), screen(), &out));
    assert(!STHSIMapTarget(card, (STHSIRect){0, 0, 10, 10}, screen(), &out));
    assert(!STHSIMapTarget(card, screen(), (STHSIRect){0, 0, NAN, 10}, &out));
    assert(!STHSIMapTarget((STHSIRect){0, 0, 20, 731}, screen(), screen(), &out));
    /* A card wider than the screen is still mapped, but the window it produces
     * must stay a real rectangle. */
    STHSIRect wide = {0, 0, 1290, 2796}, wideOut = {0};
    assert(STHSIMapTarget(card, screen(), wide, &wideOut));
    assert(wideOut.w > 80.0 && wideOut.h > 80.0);
    puts("Scene intercept policy: the card is the target, an inset scene keeps its inset, the mapping is idempotent, and a degenerate card or screen is refused");
    return 0;
}
