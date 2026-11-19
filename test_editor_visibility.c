#include <assert.h>
#include <stdio.h>
#include "EditorVisibilityMath.h"
int main(void){
 assert(STHComposerLift(410,520,490,731)==30); // input bar overlap
 assert(STHComposerLift(410,560,490,731)==70); // include toolbar below bar
 assert(STHComposerLift(400,585,490,731)==95); // include app emoji controls
 assert(STHComposerLift(350,488,490,731)==0); // already aligned: no gap correction
 assert(STHComposerLift(0,731,490,731)==0); // whole page: never move
 assert(STHComposerLift(410,520,0,731)==0); // hardware/hide
 assert(STHComposerLift(410,520,490,731)==STHComposerLift(410,520,490,731));
 assert(STHComposerLift(NAN,520,490,731)==0);
 puts("Measured composer tests passed: input+app row protection, no fixed padding, no whole-page movement");
}
