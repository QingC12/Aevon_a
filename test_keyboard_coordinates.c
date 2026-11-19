#include <assert.h>
#include <stdio.h>
#include "KeyboardCoordinates.h"
static double overlap(double y,double height) {
 double out=-1;assert(STHLocalKeyboardOverlap(0,0,400,850,0,y,400,height,0,&out));return out;
}
int main(void) {
 assert(overlap(550,300)==300);
 // Do not misread a fullscreen keyboard WINDOW as the key area.
 double out=-1;
 assert(!STHLocalKeyboardOverlap(0,0,400,850,0,0,400,850,0,&out));
 assert(!STHLocalKeyboardOverlap(0,0,400,850,0,300,400,200,0,&out));
 assert(STHLocalKeyboardOverlap(0,0,400,850,0,850,400,300,0,&out)&&out==0);
 assert(STHLocalKeyboardOverlap(0,0,400,850,450,550,400,300,0,&out)&&out==0);
 assert(STHLocalKeyboardOverlap(0,100,400,850,0,650,400,300,0,&out)&&out==300);
 assert(!STHLocalKeyboardOverlap(0,0,400,850,NAN,550,400,300,0,&out));
 // Physical-screen validation does not accept virtual fullscreen/hidden frames.
 assert(STHPhysicalFrame(0,550,400,300,400,850));
 assert(!STHPhysicalFrame(0,0,400,850,400,850));
 assert(!STHPhysicalFrame(0,850,400,300,400,850));
 assert(!STHPhysicalFrame(0,300,200,180,400,850));
 assert(!STHPhysicalFrame(0,550,400,300,400,1000));
 // Sample after one physical-to-app scaling conversion. No second division.
 assert(STHLocalKeyboardOverlap(0,0,320,680,0,440,320,240,0,&out)&&out==240);
 puts("Keyboard coordinate tests passed: real host, notifications, no fullscreen-container overlap");
 return 0;
}
