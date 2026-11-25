#ifndef STH_SCENE_INTERCEPT_H
#define STH_SCENE_INTERCEPT_H

#import <Foundation/Foundation.h>
#import "ViewportGeometry.h"

/* Give the carded application the card as its own scene rectangle.
 *
 * Answering a getter is not enough: a page prepared while the card was still
 * moving keeps the width it sampled and never asks again, so the answer cannot
 * repair it. Only a real change of the scene rectangle makes UIKit run a size
 * transition, and that transition rebuilds those pages. This is the mechanism
 * the original uses from springboard: the settings a scene is about to receive
 * are rewritten, and the new rectangle is pushed at once when it changes.
 *
 * Track() is called on the registry beat with the card that is on screen and
 * Untrack() when the card is gone. Both are main thread only and both are
 * no-ops elsewhere. A rectangle that covers the screen is tracked as native and
 * writes nothing. */
void STHSceneInterceptTrack(NSString *bundle, STHVRect card, STHVRect screen);
void STHSceneInterceptUntrack(NSString *bundle);

#endif
