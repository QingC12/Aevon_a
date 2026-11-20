#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "KeyboardGeometry.h"
int main(void) {
    assert(fabs(STHKeyboardScaleFactor(.8, 400, 500)-1.25) < .001);
    assert(fabs(STHKeyboardScaleFactor(1, 480, 500)-(500.0/480.0)) < .001);
    assert(fabs(STHKeyboardScaleFactor(.8, 600, 500)-(500.0/600.0)) < .001);
    assert(fabs(STHKeyboardScaleFactor(.4, 200, 500)-2.5) < .001);
    assert(fabs(STHKeyboardScaleFactor(1, 500, 500)-1.0) < .001);
    assert(fabs(STHKeyboardScaleFactor(0, 400, 500)-1.0) < .001);
    assert(fabs(STHKeyboardVisibleDelta(100,200,1.25,0,600)) < .001);
    assert(fabs(STHKeyboardVisibleDelta(560,400,1.25,0,600)+30) < .001);
    assert(fabs(STHKeyboardVisibleDelta(100,200,1.25,0,0)) < .001);
    puts("Keyboard geometry tests passed");
}
