#ifndef STH_EDITOR_SESSION_H
#define STH_EDITOR_SESSION_H
#include <stdbool.h>
#include <stdint.h>
typedef struct {bool active,closing;uint64_t generation;} STHEditorSession;
static inline bool STHEditorShow(STHEditorSession *s){
 bool fresh=!s->active||s->closing;
 if(fresh){s->generation++;s->active=true;s->closing=false;}
 return fresh;
}
static inline bool STHEditorWillHide(STHEditorSession *s){
 if(!s->active&&!s->closing)return false;
 s->closing=true;s->active=false;return true;
}
static inline bool STHEditorDidHide(STHEditorSession *s){
 if(!s->closing)return false; // a new WillShow invalidated the old hide
 s->closing=false;s->active=false;return true;
}
static inline void STHEditorInvalidate(STHEditorSession *s){s->active=false;s->closing=false;s->generation++;}
#endif
