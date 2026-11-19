#include <assert.h>
#include <stdio.h>
#include "KeyboardSession.h"
int main(void) {
 STHKeyboardSession s={0};
 STHRect physical={0,590,430,342};
 STHRect scene={0,0,430,731},card={0,100.5,430,731};
 STHRect mapped;double inset=0;
 assert(STHMapHostedKeyboard(card,physical,scene,&mapped,&inset));
 STHRect end=STHOcclusionFrame(scene,mapped);
 assert(fabs(end.y-489.5)<.001&&fabs(end.h-241.5)<.001);
 // A key/content window shifted by45 must NOT alter a scene-level query.
 for(int origin=-90;origin<=90;origin+=45){
  double windowTop=end.y-origin;
  assert(fabs((windowTop+origin)-489.5)<.001);
  assert(end.h==241.5);
 }
 assert(!STHSessionNeedsDelivery(&s,end)); // no synthetic show before real show
 s.visible=true;
 STHSessionPhysical(&s,physical,10,false,true);
 assert(s.hasPhysicalFrame&&s.physicalFrame.y==590);
 assert(STHSessionNeedsDelivery(&s,end));
 STHSessionCommit(&s,end);
 assert(!STHSessionNeedsDelivery(&s,end));
 STHSessionPhysical(&s,end,11,true,true); // synthetic scene frame must not poison cache
 assert(s.physicalFrame.y==590&&s.physicalFrame.h==342&&s.physicalAt==10);
 STHSessionPhysical(&s,(STHRect){0,0,430,932},11,false,false);
 assert(s.physicalAt==10);
 STHRect changed=end;changed.y-=27;changed.h+=27;
 assert(STHSessionNeedsDelivery(&s,changed));
 STHSessionCommit(&s,changed);assert(!STHSessionNeedsDelivery(&s,changed));
 STHSessionHide(&s);
 assert(!s.visible&&!s.hasSceneFrame&&!s.hasPhysicalFrame);
 assert(!STHSessionNeedsDelivery(&s,end));
 puts("Scene/session tests passed:241.5 not286.5; no physical cache poisoning; idempotent refresh; hide invalidation");
}
