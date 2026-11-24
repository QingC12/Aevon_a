#include "AppSceneReflowPolicy.h"
#include <assert.h>
#include <stdio.h>

static STHRPolicyInput validInput(void) {
    return (STHRPolicyInput){
        .inject = true,
        .settingMaskPresent = true,
        .settingBit31 = true,
        .queryIsMainScreen = true,
        .sceneIsOnMainScreen = true,
        .hostedLayout = true,
        .sceneConnected = true,
        .sceneUsable = true,
        .sceneBoundsValid = true,
        .physicalBoundsValid = true,
        .sceneSize = {390, 740},
        .physicalSize = {390, 844}
    };
}

int main(void) {
    STHRPolicyInput p = validInput();
    assert(STHRShouldReflow(&p));

    p.sceneSize = (STHRSize){390, 844};
    assert(!STHRShouldReflow(&p));
    p.sceneSize = (STHRSize){844, 390};
    assert(!STHRShouldReflow(&p));

    p = validInput(); p.sceneBoundsValid = false;
    assert(!STHRShouldReflow(&p));
    p = validInput(); p.physicalBoundsValid = false;
    assert(!STHRShouldReflow(&p));
    p = validInput(); p.sceneSize = (STHRSize){NAN, 740};
    assert(!STHRShouldReflow(&p));
    p = validInput(); p.physicalSize = (STHRSize){390, 0};
    assert(!STHRShouldReflow(&p));

    p = validInput(); p.inject = false;
    assert(!STHRShouldReflow(&p));
    p = validInput(); p.settingMaskPresent = false;
    assert(!STHRShouldReflow(&p));
    p = validInput(); p.settingBit31 = false;
    assert(!STHRShouldReflow(&p));

    p = validInput(); p.sceneConnected = false;
    assert(!STHRShouldReflow(&p));
    p = validInput(); p.sceneUsable = false;
    assert(!STHRShouldReflow(&p));
    /* A floating card resizes and animates while it is neither foreground
     * active nor the key scene: neither fact may decide the layout size. */
    p = validInput(); p.sceneUsable = true;
    assert(STHRShouldReflow(&p));
    p = validInput(); p.hostedLayout = false;
    assert(!STHRShouldReflow(&p));
    p = validInput(); p.queryIsMainScreen = false;
    assert(!STHRShouldReflow(&p));
    p = validInput(); p.sceneIsOnMainScreen = false;
    assert(!STHRShouldReflow(&p));

    /* Updated native scene sizes flow through directly, without card scale. */
    p = validInput(); p.sceneSize = (STHRSize){414, 710};
    assert(STHRShouldReflow(&p));
    assert(p.sceneSize.width == 414 && p.sceneSize.height == 710);
    p.sceneSize = (STHRSize){428, 680};
    assert(STHRShouldReflow(&p));
    assert(p.sceneSize.width == 428 && p.sceneSize.height == 680);

    puts("PASS: reflow policy gates, physical fullscreen, scene size updates");
    return 0;
}
