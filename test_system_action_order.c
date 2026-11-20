#include <assert.h>
#include <stdint.h>
#include "SystemActionOrder.h"
typedef struct{uintptr_t name,owner,id,kind;} Record;
static unsigned priority(const void *r,void *context){(void)context;return (unsigned)((const Record *)r)->kind;}
int main(void){
 Record records[]={{10,11,100,2},{20,21,200,1},{30,31,300,2},{40,41,400,0},{50,51,500,2}};
 STHSystemStableFront(records,5,sizeof(Record),priority,0);
 assert(records[0].id==400&&records[0].name==40&&records[0].owner==41);
 assert(records[1].id==200&&records[1].name==20&&records[1].owner==21);
 assert(records[2].id==100&&records[3].id==300&&records[4].id==500);
 Record copy[5];memcpy(copy,records,sizeof(copy));
 for(int i=0;i<100;i++)STHSystemStableFront(records,5,sizeof(Record),priority,0);
 assert(!memcmp(copy,records,sizeof(copy)));
 Record ordinary[]={{10,11,100,2},{20,21,200,2}};Record same[2];memcpy(same,ordinary,sizeof(same));
 STHSystemStableFront(ordinary,2,32,priority,0);assert(!memcmp(same,ordinary,sizeof(same)));
 STHSystemStableFront(ordinary,2,16,priority,0);assert(!memcmp(same,ordinary,sizeof(same)));
 STHSystemStableFront(0,2,32,priority,0);
 return 0;
}
