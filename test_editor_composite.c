#include <assert.h>
#include <stdio.h>
#include "EditorCompositeMath.h"
#include "EditorCompositeProfiles.h"
static void near(double a,double b){assert(fabs(a-b)<.001);}
int main(void){
 assert(STHCompositeProfile("com.tencent.mqq")==0);
 assert(STHCompositeProfile("com.openminis.app")==0);
 assert(STHCompositeProfile("com.tencent.xin")==0);
 assert(STHCompositeProfile("com.coolapk.app")==1);
 assert(STHCompositeProfile("com.feng.New.WPForumClient")==2);
 assert(STHCompositeProfile("com.ss.iphone.ugc.Aweme")==3);
 assert(!STHComposerOwner(382,20,430,731,false,false)); // actual Douyin log leaf
 assert(!STHComposerOwner(398,82.625,430,731,true,true));
 assert(STHComposerOwner(414,44,430,731,false,false)); // contacts entry owner
 assert(STHComposerOwner(430,175,430,731,false,false)); // reply+toolbar owner
 assert(!STHComposerOwner(430,305,430,731,false,false));
 STHRect text={16,357,398,82.625},small=text,parent={0,330,430,175};
 assert(STHExpandOwner(small,parent,text,731,500,4));
 assert(!STHExpandOwner(small,parent,text,731,439.625,4)); // padded only
 STHRect reply={0,365.625,430,112};
 assert(STHCompositeRow(reply,(STHRect){0,489.625,430,44},text,731,true,4,false));
 STHRect row1={0,365.625,430,168};
 assert(STHCompositeRow(row1,(STHRect){0,545.625,430,48},text,731,true,7,false));
 assert(!STHCompositeRow(reply,(STHRect){0,489.625,430,500},text,731,true,8,true));
 assert(!STHCompositeRow(reply,(STHRect){0,489.625,430,44},text,731,false,4,false));
 // Moving ONE common owner leaves native child layout unchanged. Each layout
 // pass runs with the original transform, then the same correction is applied.
 for(int cycle=0;cycle<100;cycle++){
  double ownerBottom=(cycle%2)?489.5:462.5,key=ownerBottom-17;
  double shift=STHRefinedLift(0,ownerBottom,key,300,193.5,731);
  for(int layout=0;layout<20;layout++){
   double untransformedBottom=ownerBottom; // neutral layout contract
   near(STHRefinedLift(shift,untransformedBottom-shift,key,300,193.5,731),shift);
   near(untransformedBottom-shift,key);
  }
 }
 STHResidualHistory history={0};
 double cap=STHBoundedResidual(&history,17,489.5,472.5,0);near(cap,17);history.after=472.5;
 cap=STHBoundedResidual(&history,34,489.5,472.5,17);near(cap,34);history.after=472.5;
 cap=STHBoundedResidual(&history,51,489.5,472.5,34);near(cap,34); // no17,34,51,... growth
 cap=STHBoundedResidual(&history,40,500,460,34);near(cap,40); // genuine new target allowed
 puts("Composite cases passed: keep QQ/Minis/WeChat, reject20pt leaf, complete reply owner+2rows,100x20 native relayouts and bounded feedback");
}
