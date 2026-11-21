#ifndef APP_SCENE_REFLOW_H
#define APP_SCENE_REFLOW_H

#if !defined(STH_VIEWPORT_CLIENT_TEST)
#import <UIKit/UIKit.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Reads the saved UIKit implementation even after UIScreen.bounds is hooked. */
CGRect STHVUnmodifiedScreenBounds(UIScreen *screen);

/* Idempotent; also invoked automatically when the module is loaded. */
void STHVInstallAppSceneReflow(void);

#ifdef __cplusplus
}
#endif
#endif
