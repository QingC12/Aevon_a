#ifndef STH_SCENE_PUSH_H
#define STH_SCENE_PUSH_H

#import <Foundation/Foundation.h>
#import "ViewportGeometry.h"

/* The card is not only answered, it is published to the application as its own
 * scene geometry. A hosted application keeps a page laid out for whatever width
 * it sampled while the card was still moving, and it never asks again, so no
 * amount of answering the screen getter repairs that page. Only a real change of
 * the scene rectangle makes UIKit run a size transition, which is what rebuilds
 * those pages.
 *
 * Both functions are main-thread only and are no-ops elsewhere. The first one
 * derives the scene frame from the card the same way for every ratio, so a
 * second call with an unchanged card writes nothing. The second one puts the
 * frame the application had before the first push back. */
void STHScenePushViewport(NSString *bundle, STHVRect card, STHVRect screen);
void STHScenePushRestore(NSString *bundle);

#endif
