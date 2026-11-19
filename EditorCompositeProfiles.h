#ifndef STH_EDITOR_COMPOSITE_PROFILES_H
#define STH_EDITOR_COMPOSITE_PROFILES_H
#include <string.h>
static inline int STHCompositeProfile(const char *bundle){
 if(!bundle)return 0;
 if(strcmp(bundle,"com.coolapk.app")==0)return 1;
 if(strcmp(bundle,"com.feng.New.WPForumClient")==0)return 2;
 if(strcmp(bundle,"com.ss.iphone.ugc.Aweme")==0)return 3;
 return 0;
}
#endif
