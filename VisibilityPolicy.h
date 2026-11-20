#ifndef STH_VISIBILITY_POLICY_H
#define STH_VISIBILITY_POLICY_H
#include <stdbool.h>
#include <stdint.h>
typedef struct {
 unsigned active;
 unsigned pending;
 double deadline[3];
} STHVisibilityPolicy;
static inline void STHVisibilityEvent(STHVisibilityPolicy *s,unsigned bit,bool visible,double now){
 for(unsigned i=0;i<3;i++)if(bit==(1u<<i)){
  if(visible){s->active|=bit;s->pending|=bit;s->deadline[i]=now+.35;}
  else{s->active&=~bit;s->pending&=~bit;s->deadline[i]=0;}
 }
}
static inline bool STHVisibilitySample(STHVisibilityPolicy *s,unsigned known,unsigned observed,double now){
 for(unsigned i=0;i<3;i++){
  unsigned bit=1u<<i;
  if(!(known&bit))continue;
  if(observed&bit){s->active|=bit;s->pending&=~bit;}
  else if(!(s->pending&bit)||now>=s->deadline[i]){s->active&=~bit;s->pending&=~bit;}
 }
 return s->active!=0;
}
typedef struct {
 bool desired;
 unsigned setterDepth,forcedDepth;
} STHHiddenIntent;
static inline bool STHHiddenSetterBegin(STHHiddenIntent *s,bool value,bool masked){
 if(s->setterDepth==0&&s->forcedDepth==0)s->desired=value;
 s->setterDepth++;return masked?true:value;
}
static inline void STHHiddenSetterEnd(STHHiddenIntent *s){if(s->setterDepth)s->setterDepth--;}
#endif
