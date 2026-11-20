#include <assert.h>
#include <stddef.h>
#include "ChooserMotion.h"
int main(void){
 assert(STHChooserDiameter(43,51.6)>20&&STHChooserDiameter(43,51.6)<31);
 assert(STHChooserDiameter(100,50)==50);
 assert(STHChooserDiameter(10,50)==0);
 assert(STHChooserDiameter(NAN,50)==0);
 assert(STHChooserAlpha(0)==0&&STHChooserAlpha(.5)==0&&STHChooserAlpha(1)==1&&STHChooserAlpha(2)==1);
 STHChooserSpring motion={0};
 double first=STHChooserSpringStep(&motion,1,1./30,1.1);assert(first>0&&first<1);
 for(int i=0;i<120;i++)STHChooserSpringStep(&motion,1,1./30,1.1);
 assert(fabs(motion.x-1)<.001);
 for(int i=0;i<120;i++)STHChooserSpringStep(&motion,0,1./30,.7);
 assert(fabs(motion.x)<.001);
 for(int i=0;i<100;i++)STHChooserSpringStep(&motion,i%2?0:1,.10,.35);
 assert(isfinite(motion.x)&&fabs(motion.x)<3);
 return 0;
}
