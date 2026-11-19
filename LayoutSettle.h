#ifndef STH_LAYOUT_SETTLE_H
#define STH_LAYOUT_SETTLE_H
#include "LayoutMath.h"
#include <string.h>
// Debounce the PAIR, not independent keyboard/card rectangles. A short-lived
// notification top (e.g.590->545->590 in18ms) must not become an editor target.
typedef struct {
 bool active,haveCandidate,haveCommitted;
 double candidateAt,notBefore;
 STHRect candidateCard,candidateKeys,committedCard,committedKeys;
 unsigned generation;
} STHLayoutSettle;
static inline bool STHSameRect(STHRect a,STHRect b) {
 return fabs(a.x-b.x)<=.5&&fabs(a.y-b.y)<=.5&&fabs(a.w-b.w)<=.5&&fabs(a.h-b.h)<=.5;
}
static inline void STHSettleBegin(STHLayoutSettle *s,double now) {
 unsigned generation=s->generation+1;memset(s,0,sizeof(*s));
 s->active=true;s->generation=generation;s->notBefore=now+.16;
}
static inline bool STHSettleSample(STHLayoutSettle *s,STHRect card,STHRect keys,double now) {
 if(!s->active||!STHFiniteRect(card)||!STHFiniteRect(keys))return false;
 if(!s->haveCandidate||!STHSameRect(card,s->candidateCard)||!STHSameRect(keys,s->candidateKeys)){
  s->candidateCard=card;s->candidateKeys=keys;s->candidateAt=now;s->haveCandidate=true;return false;
 }
 if(now<s->notBefore||now-s->candidateAt<.12)return false;
 if(s->haveCommitted&&STHSameRect(card,s->committedCard)&&STHSameRect(keys,s->committedKeys))return false;
 s->committedCard=card;s->committedKeys=keys;s->haveCommitted=true;return true;
}
static inline void STHSettleEnd(STHLayoutSettle *s) {s->active=false;s->haveCandidate=false;s->haveCommitted=false;s->generation++;}
#endif
