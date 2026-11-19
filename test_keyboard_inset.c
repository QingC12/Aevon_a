#include <assert.h>
#include <stdio.h>
#include "KeyboardInsetMath.h"
int main(void) {
 // Legacy over-lift 430, actual window intersection 300: remove extra 130.
 assert(STHReduceKeyboardInset(430,0,0,400,850,0,550,400,300,0)==300);
 // The same keyboard after moving the target/window origin is converted first.
 assert(STHReduceKeyboardInset(430,0,100,400,850,0,650,400,300,0)==300);
 // Do not increase native insets, affect hardware/floating/off-screen keyboards,
 // or consume unrelated horizontal windows.
 assert(STHReduceKeyboardInset(250,0,0,400,850,0,550,400,300,0)==250);
 assert(STHReduceKeyboardInset(0,0,0,400,850,0,550,400,300,0)==0);
 assert(STHReduceKeyboardInset(430,0,0,400,850,0,850,400,300,0)==430);
 assert(STHReduceKeyboardInset(430,0,0,400,850,0,300,200,180,0)==430);
 assert(STHReduceKeyboardInset(430,0,0,400,850,450,550,400,300,0)==430);
 assert(STHReduceKeyboardInset(430,0,0,400,850,450,550,400,300,1)==300);
 assert(STHReduceKeyboardInset(430,0,0,400,850,NAN,550,400,300,0)==430);
 puts("Keyboard inset tests passed: correct overlap, no duplicated lift, scoped fallbacks");
}
