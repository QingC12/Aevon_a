#ifndef STH_SYSTEM_ACTION_ORDER_H
#define STH_SYSTEM_ACTION_ORDER_H
#include <stddef.h>
#include <string.h>
// App(name:String,id:String) is four machine words in the pinned arm64e
// image. Move complete values only, without allocating/destroying any String.
typedef unsigned (*STHSystemRecordPriority)(const void *record,void *context);
static inline void STHSystemStableFront(void *records,size_t count,size_t stride,STHSystemRecordPriority priority,void *context){
 if(!records||!priority||stride!=32||count>65536)return;
 unsigned char *bytes=(unsigned char *)records;
 size_t destination=0;
 for(unsigned rank=0;rank<2;rank++){
  for(size_t i=destination;i<count;i++){
   if(priority(bytes+i*stride,context)!=rank)continue;
   unsigned char value[32];memcpy(value,bytes+i*stride,32);
   memmove(bytes+(destination+1)*stride,bytes+destination*stride,(i-destination)*stride);
   memcpy(bytes+destination*stride,value,32);destination++;break;
  }
 }
}
#endif
