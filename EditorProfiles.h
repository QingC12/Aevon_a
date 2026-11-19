#ifndef STH_EDITOR_PROFILES_H
#define STH_EDITOR_PROFILES_H
#include <string.h>
typedef enum {STHEditorCompatible,STHEditorCompact,STHEditorTransparentTail} STHEditorProfile;
static inline STHEditorProfile STHProfileForBundle(const char *bundle){
 if(!bundle)return STHEditorCompatible;
 if(strcmp(bundle,"com.feng.New.WPForumClient")==0)return STHEditorTransparentTail;
 if(strcmp(bundle,"com.tencent.xin")==0||strcmp(bundle,"com.coolapk.app")==0||
    strcmp(bundle,"com.ss.iphone.ugc.Aweme")==0)return STHEditorCompact;
 return STHEditorCompatible;
}
#endif
