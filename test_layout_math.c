#include <assert.h>
#include <stdio.h>
#include "LayoutMath.h"
static void test(STHRect card,STHRect keys,STHRect app,double expected) {
 STHRect local;double inset=-1;
 assert(STHMapHostedKeyboard(card,keys,app,&local,&inset));
 assert(fabs(inset-expected)<.001);
 if(inset>0&&inset<app.h){
  // Wherever the card is, the visible editor's bottom maps to keyboard top.
  double editor=card.y+((app.y+app.h-inset)-app.y)*(card.h/app.h);
  assert(fabs(editor-keys.y)<.001);
 }
}
int main(void){
 STHRect app={0,0,400,800},keyboard={0,550,400,300};
 test((STHRect){0,100,400,800},keyboard,app,350);
 test((STHRect){100,400,200,400},keyboard,app,500);
 test((STHRect){100,100,200,400},keyboard,app,0); // Top: unobscured.
 test((STHRect){100,600,200,400},keyboard,app,800); // Entire editor is under keys.
 test((STHRect){40,300,320,640},keyboard,app,487.5);
 test((STHRect){0,-100,400,800},keyboard,app,150);
 test((STHRect){0,100,400,800},(STHRect){500,550,400,300},app,0);
 STHRect result;double overlap;
 assert(!STHMapHostedKeyboard((STHRect){0,0,0,100},keyboard,app,&result,&overlap));
 uint64_t packed=0;STHRect card={-150.125,220.5,390,844};assert(STHPackRect(card,&packed));
 STHRect decoded=STHUnpackRect(packed);
 assert(decoded.x==card.x&&decoded.y==card.y&&decoded.w==card.w&&decoded.h==card.h);
 assert(!STHPackRect((STHRect){5000,0,400,800},&packed));
 puts("Host mapping passed: small/large, top/middle/bottom, negative origin, fixed-point transport");
}
