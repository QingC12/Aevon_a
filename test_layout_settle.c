#include <assert.h>
#include <stdio.h>
#include "LayoutSettle.h"
static void firstOpen(double initialTop,double transientTop) {
 STHLayoutSettle s={0};STHRect original={43,173.6,344,584.8},final={0,100.5,430,731};
 STHRect initial={0,initialTop,430,932-initialTop};
 STHRect transient={0,transientTop,430,932-transientTop},settled={0,590,430,342};
 STHSettleBegin(&s,0);
 assert(!STHSettleSample(&s,original,initial,0));
 assert(!STHSettleSample(&s,final,initial,.001));
 assert(!STHSettleSample(&s,final,transient,.02));
 assert(!STHSettleSample(&s,final,settled,.055));
 assert(!STHSettleSample(&s,final,settled,.10));
 assert(STHSettleSample(&s,final,settled,.18));
 assert(s.committedKeys.y==590&&s.committedCard.w==430);
 // Replay another 18ms bad notification: do not emit241.5->286.5->241.5.
 assert(!STHSettleSample(&s,final,transient,.30));
 assert(!STHSettleSample(&s,final,settled,.318));
 assert(!STHSettleSample(&s,final,settled,.48));
 assert(s.committedKeys.y==590);
 // Real sustained candidate/keyboard change is accepted, not locked forever.
 assert(!STHSettleSample(&s,final,initial,1.0));
 if(initialTop!=590)assert(STHSettleSample(&s,final,initial,1.13));
 STHSettleEnd(&s);assert(!STHSettleSample(&s,final,settled,2.0));
}
int main(void) {
 // Values copied from2.0.8 host log; no app IDs or content needed.
 for(int i=0;i<30;i++){firstOpen(590,545);firstOpen(563,518);}
 puts("60 show cycles replayed: no pre-expansion card or18-55ms keyboard transients committed; genuine changes allowed");
 return 0;
}
