#include <assert.h>
#include <stdio.h>
#include "GestureRules.h"

int main(void)
{
    STHYellowMode move = STHYellowNext(STHYellowPending, .10, 1.0, 8.0);
    assert(move == STHYellowMoving);
    assert(STHYellowNext(move, .40, 8.0, 80.0) == STHYellowMoving);
    assert(!STHYellowCloses(move, 0.0, -80.0));

    STHYellowMode held = STHYellowNext(STHYellowPending, .25, 2.0, 2.0);
    assert(held == STHYellowCloseArmed);
    assert(STHYellowNext(held, .26, 2.0, 32.0) == STHYellowCloseArmed);
    assert(STHYellowCloses(held, 3.0, -24.0));
    assert(!STHYellowCloses(held, 0.0, -23.0));
    assert(!STHYellowCloses(held, 0.0, 40.0));
    assert(!STHYellowCloses(held, 45.0, -30.0));
    assert(STHYellowNext(STHYellowPending, .249, 0.0, 2.0) == STHYellowPending);
    assert(STHYellowNext(STHYellowPending, .30, 0.0, 28.0) == STHYellowCloseArmed);
    puts("Yellow gesture rules passed");
    return 0;
}
