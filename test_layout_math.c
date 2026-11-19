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
 // Device log: Aweme full-width card y=86.1667 height731, keyboard top590.
 // Full remote keyboard height342 is NOT the occlusion227.1667.
 STHRect scene={0,0,430,731},mapped;double inset=0;
 assert(STHMapHostedKeyboard((STHRect){0,86.1666667,430,731},(STHRect){0,590,430,342},scene,&mapped,&inset));
 STHRect notice=STHOcclusionFrame(scene,mapped);
 assert(fabs(inset-227.1666667)<.001&&fabs(notice.h-inset)<.001);
 assert(fabs((scene.y+scene.h-notice.y)-notice.h)<.001);
 assert(fabs(notice.y+86.1666667-590)<.001);
 // Including the notified toolbar moves the input bottom up by27 physical pt,
 // not a blanket app-specific offset.
 assert(STHMapHostedKeyboard((STHRect){0,86.1666667,430,731},(STHRect){0,563,430,369},scene,&mapped,&inset));
 notice=STHOcclusionFrame(scene,mapped);assert(fabs(notice.h-254.1666667)<.001);
 notice=STHOcclusionFrame(scene,(STHRect){0,900,430,342});assert(notice.h==0&&notice.y==731);
 STHRect result;double overlap;
 assert(!STHMapHostedKeyboard((STHRect){0,0,0,100},keyboard,app,&result,&overlap));
 uint64_t packed=0;STHRect card={-150.125,220.5,390,844};assert(STHPackRect(card,&packed));
 STHRect decoded=STHUnpackRect(packed);
 assert(decoded.x==card.x&&decoded.y==card.y&&decoded.w==card.w&&decoded.h==card.h);
 assert(!STHPackRect((STHRect){5000,0,400,800},&packed));
 puts("Host mapping passed: small/large, top/middle/bottom, negative origin, fixed-point transport");
}
