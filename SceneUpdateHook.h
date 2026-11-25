#ifndef STH_SCENE_UPDATE_HOOK_H
#define STH_SCENE_UPDATE_HOOK_H

#import <Foundation/Foundation.h>
#import "ViewportGeometry.h"

/* The private scene update hooks the original Stheno uses from springboard.
 *
 * The port dropped them and answered UIScreen.bounds instead, so the scene the
 * application is hosted in keeps whatever size the system calculated. When a
 * custom ratio makes the card narrower than that, the application still lays
 * itself out for the old width and the right hand column stays at the old right
 * edge, outside the card.
 *
 * This module puts the hooks back: the settings a scene is about to receive are
 * intercepted and their SIZE is replaced by the card the application is being
 * shown in. Only the size is written. The origin, the level, the interface
 * orientation and every other setting the system sent are left exactly as they
 * were, so nothing else about the scene changes.
 *
 * Track() is called on the registry beat with the card that is on screen and
 * Untrack() when the card is gone. Both are main thread only, both write
 * nothing for a card that covers the screen, and both are no-ops outside
 * springboard. */
void STHSceneUpdateHookTrack(NSString *bundle, STHVRect card, STHVRect screen);
void STHSceneUpdateHookUntrack(NSString *bundle);

#endif
