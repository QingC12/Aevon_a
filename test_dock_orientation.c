#include <assert.h>
#include <stdio.h>
#include "DockOrientation.h"
int main(void) {
    assert(STHDockUsesNativeReflow(1));
    assert(STHDockUsesNativeReflow(2));
    assert(!STHDockUsesNativeReflow(3));
    assert(STHDockMayApply(0, -1, 1));
    assert(STHDockMayApply(0, 1, 2));
    assert(!STHDockMayApply(1, -1, 1));
    assert(STHDockMayApply(1, 1, 1));
    assert(!STHDockMayApply(0, 1, 3));
    puts("Dock orientation policy passed");
    return 0;
}
