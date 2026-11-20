#include <assert.h>
#include "VisibilityPolicy.h"
int main(void){
 STHVisibilityPolicy p={0};
 STHVisibilityEvent(&p,2,true,0);assert(STHVisibilitySample(&p,7,0,.1));
 assert(!STHVisibilitySample(&p,7,0,.36));
 STHVisibilityEvent(&p,2,true,1);assert(STHVisibilitySample(&p,7,2,1.1));
 assert(!STHVisibilitySample(&p,7,0,1.2)); // no delegate didDismiss needed
 STHVisibilityEvent(&p,2,true,2);assert(STHVisibilitySample(&p,7,2,2.1));
 STHVisibilityEvent(&p,4,true,2.2);assert(STHVisibilitySample(&p,7,4,2.3));
 assert(p.active==4);assert(STHVisibilitySample(&p,7,4,4));
 assert(!STHVisibilitySample(&p,7,0,5));
 STHVisibilityEvent(&p,2,true,6);STHVisibilityEvent(&p,1,true,6);
 assert(STHVisibilitySample(&p,7,3,6.1));STHVisibilityEvent(&p,2,false,6.2);
 assert(STHVisibilitySample(&p,7,1,6.3));assert(p.active==1);
 assert(!STHVisibilitySample(&p,7,0,7));
 STHVisibilityEvent(&p,4,true,8);assert(STHVisibilitySample(&p,3,0,9)); // lock query unknown
 assert(!STHVisibilitySample(&p,7,0,9.1));
 for(int i=0;i<100;i++){
  STHVisibilityEvent(&p,2,true,10+i);assert(STHVisibilitySample(&p,7,2,10+i));
  assert(!STHVisibilitySample(&p,7,0,10.1+i));
 }
 STHHiddenIntent intent={0};
 assert(STHHiddenSetterBegin(&intent,false,true));
 assert(STHHiddenSetterBegin(&intent,true,true));
 STHHiddenSetterEnd(&intent);STHHiddenSetterEnd(&intent);
 assert(!intent.desired&&!intent.setterDepth);
 intent.forcedDepth++;
 assert(STHHiddenSetterBegin(&intent,true,true));STHHiddenSetterEnd(&intent);
 intent.forcedDepth--;assert(!intent.desired);
 assert(!STHHiddenSetterBegin(&intent,intent.desired,false));STHHiddenSetterEnd(&intent);
 assert(STHHiddenSetterBegin(&intent,true,true));STHHiddenSetterEnd(&intent);assert(intent.desired);
 return 0;
}
