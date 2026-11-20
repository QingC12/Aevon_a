#include <assert.h>
#include "SystemActionGate.h"
int main(void){
 STHSystemActionGate gate={0};
 assert(!STHSystemActionBegin(NULL,1));
 assert(!STHSystemActionBegin(&gate,NAN));
 assert(STHSystemActionBegin(&gate,0));
 uint64_t first=gate.generation;
 for(int i=0;i<100;i++)assert(!STHSystemActionBegin(&gate,i*.01));
 assert(!STHSystemActionFinish(&gate,first+1));
 assert(STHSystemActionFinish(&gate,first));
 assert(!STHSystemActionFinish(&gate,first));
 assert(!STHSystemActionBegin(&gate,.69));
 assert(STHSystemActionBegin(&gate,.71));
 assert(!STHSystemActionFinish(&gate,first));
 assert(STHSystemActionFinish(&gate,gate.generation));
 assert(STHSystemActionBegin(&gate,2));
 return 0;
}
