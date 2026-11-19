#include <assert.h>
#include <stdio.h>
#include "KeyboardPlaneMath.h"
int main(void){
 STHRect screen={0,0,430,932},host={0,590,430,342};
 assert(!STHSelectKeyboardPlane((STHRect){0,529,430,403},0,host,screen,0,host));
 assert(!STHSelectKeyboardPlane((STHRect){0,533,430,399},0,host,screen,0,host));
 assert(STHSelectKeyboardPlane(host,3,host,screen,0,host));
 assert(!STHSelectKeyboardPlane((STHRect){0,529,430,403},2,host,screen,3,host));
 assert(!STHSelectKeyboardPlane((STHRect){0,529,430,403},3,host,screen,3,host));
 assert(STHSelectKeyboardPlane(host,3,host,screen,3,(STHRect){0,529,430,403}));
 assert(!STHSelectKeyboardPlane((STHRect){0,0,430,932},3,host,screen,0,host));
 STHRect assistant={0,573,430,17};
 assert(STHKeyboardConnectedRow(host,assistant,screen,true,false));
 assert(!STHKeyboardConnectedRow(host,(STHRect){0,529,430,61},screen,false,false));
 assert(!STHKeyboardConnectedRow(host,assistant,screen,true,true));
 assert(!STHKeyboardConnectedRow(host,(STHRect){0,500,430,17},screen,true,false));
 // With the17pt visible assistant, both scene methods land on472.5. A broad
 // reply/toolbar host at529/533 cannot turn this into428.5/432.5.
 STHRect mapped;double inset=0;
 assert(STHMapHostedKeyboard((STHRect){0,100.5,430,731},(STHRect){0,573,430,359},(STHRect){0,0,430,731},&mapped,&inset));
 assert(fabs(mapped.y-472.5)<.001&&fabs(inset-258.5)<.001);
 puts("Keyboard source cases passed: broad529/533 hosts rejected; exact590 keyplane plus connected573 assistant accepted");
 return 0;
}
