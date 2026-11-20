#include <assert.h>
#include <stdio.h>
#include "DockOrientation.h"
int main(void) {
    assert(STHDockUsesNativeReflow(1));
    assert(STHDockUsesNativeReflow(2));
    assert(!STHDockUsesNativeReflow(3));
    assert(!STHDockUsesNativeReflow(4));
    puts("Dock orientation: portrait queue writes only; landscape leaves native offsets untouched");
    return 0;
}
