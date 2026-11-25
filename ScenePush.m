// Publish the card as the application's own scene rectangle.
//
// Every approach that only answers a getter runs into the same wall: a hosted
// application prepares the next page while the card is still animating, keeps
// the width it sampled, and never asks again for that page. Answering a later
// question cannot repair a page that has stopped asking, and marking views dirty
// does not either, because the page does not lay itself out from the card at
// all - it reads a scene rectangle once. The only input that makes UIKit run a
// real size transition, and therefore the only one that makes every page cache
// be rebuilt, is a changed scene frame delivered through the scene's own update
// path. That is what this file does, from springboard, over the private scene
// objects the system already keeps for the carded application.
//
// Nothing here is linked and no private header is imported: the classes are
// resolved by name and the few messages used are declared on NSObject below, so
// the compiler emits the right call for each return type while every send is
// still behind respondsToSelector. A wrong guess must be a no-op, never a
// springboard crash.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#import "ScenePush.h"
#import "ViewportDiagnostics.h"

@interface NSObject (STHScenePrivate)
+ (id)sharedInstance;
- (id)settings;
- (CGRect)frame;
- (void)setFrame:(CGRect)frame;
- (void)updateSettings:(id)settings
    withTransitionContext:(id)context
              completion:(void (^)(BOOL success, NSError *error))completion;
- (id)mainScene;
- (id)scenes;
- (id)scene;
- (id)allScenes;
- (id)sceneWithIdentifier:(NSString *)identifier;
- (NSString *)identifier;
- (id)applicationWithBundleIdentifier:(NSString *)identifier;
@end

static STHVRect sthVRect(CGRect rect) {
  return (STHVRect){rect.origin.x, rect.origin.y, rect.size.width, rect.size.height};
}
static BOOL sthSameRect(CGRect a, CGRect b) {
  return fabs(a.origin.x - b.origin.x) < 0.5 && fabs(a.origin.y - b.origin.y) < 0.5 &&
         fabs(a.size.width - b.size.width) < 0.5 && fabs(a.size.height - b.size.height) < 0.5;
}
/* A rectangle is kept as four numbers. NSValue only knows how to box a CGRect
 * once UIKit's geometry category is linked, and this module deliberately needs
 * nothing but Foundation, so the four components are stored directly. */
static void sthStoreRect(NSMutableDictionary *entry, NSString *key, CGRect rect) {
  entry[key] = @[ @(rect.origin.x), @(rect.origin.y), @(rect.size.width), @(rect.size.height) ];
}
static BOOL sthLoadRect(NSMutableDictionary *entry, NSString *key, CGRect *rect) {
  NSArray *value = entry[key];
  if (![value isKindOfClass:NSArray.class] || value.count != 4) return NO;
  if (rect)
    *rect = CGRectMake([value[0] doubleValue], [value[1] doubleValue],
                       [value[2] doubleValue], [value[3] doubleValue]);
  return YES;
}
/* Every send below is one declared message behind its own guard. The guard is
 * the whole safety property: these objects come from the system, their exact
 * shape differs between releases, and a message this build does not know how to
 * send must be dropped rather than delivered to an object that cannot take it. */
static id sthSettings(id scene) {
  return [scene respondsToSelector:@selector(settings)] ? [scene settings] : nil;
}
static id sthWrappedScene(id handle) {
  return [handle respondsToSelector:@selector(scene)] ? [handle scene] : nil;
}
static id sthMainScene(id application) {
  return [application respondsToSelector:@selector(mainScene)] ? [application mainScene] : nil;
}
static id sthScenes(id application) {
  return [application respondsToSelector:@selector(scenes)] ? [application scenes] : nil;
}
static id sthAllScenes(id manager) {
  return [manager respondsToSelector:@selector(allScenes)] ? [manager allScenes] : nil;
}
static id sthIdentifier(id scene) {
  return [scene respondsToSelector:@selector(identifier)] ? [scene identifier] : nil;
}
static id sthSceneByIdentifier(id manager, NSString *bundle) {
  return [manager respondsToSelector:@selector(sceneWithIdentifier:)]
             ? [manager sceneWithIdentifier:bundle]
             : nil;
}

/* SpringBoard keeps one controller for the installed applications; the scene
 * manager keeps one scene per hosted application identifier. Either path is
 * enough, but the application object does not always hand back the scene
 * itself: on some releases it returns a handle that wraps one, and only the
 * wrapped object carries the settings. Everything is therefore unwrapped before
 * it is used, and a candidate without settings is never treated as a scene. */
static id sthShared(NSString *className) {
  Class cls = NSClassFromString(className);
  if (!cls || ![cls respondsToSelector:@selector(sharedInstance)]) return nil;
  return [(id)cls sharedInstance];
}
static id sthUnwrapScene(id candidate) {
  if (!candidate) return nil;
  if ([candidate respondsToSelector:@selector(settings)]) return candidate;
  id inner = sthWrappedScene(candidate);
  if (inner && [inner respondsToSelector:@selector(settings)]) return inner;
  return nil;
}
static id sthSceneFor(NSString *bundle) {
  id controller = sthShared(@"SBApplicationController");
  id application = nil;
  if ([controller respondsToSelector:@selector(applicationWithBundleIdentifier:)])
    application = [controller applicationWithBundleIdentifier:bundle];
  if (application) {
    id scene = sthUnwrapScene(sthMainScene(application));
    if (scene) return scene;
    id scenes = sthScenes(application);
    if ([scenes isKindOfClass:NSArray.class] || [scenes isKindOfClass:NSSet.class]) {
      for (id candidate in (id)scenes) {
        scene = sthUnwrapScene(candidate);
        if (scene) return scene;
      }
    }
  }
  id manager = sthShared(@"FBSceneManager");
  id byIdentifier = sthUnwrapScene(sthSceneByIdentifier(manager, bundle));
  if (byIdentifier) return byIdentifier;
  // Last resort: the manager may only expose the whole workspace. The
  // identifier of an application scene is its bundle identifier, so an exact
  // match is the same answer a direct lookup would have given.
  id all = sthAllScenes(manager);
  if (![all isKindOfClass:NSArray.class] && ![all isKindOfClass:NSSet.class]) return nil;
  for (id candidate in all) {
    if (![candidate respondsToSelector:@selector(identifier)]) continue;
    if (![sthIdentifier(candidate) isEqualToString:bundle]) continue;
    id scene = sthUnwrapScene(candidate);
    if (scene) return scene;
  }
  return nil;
}

/* The frame is the only setting written. The mutable copy carries every other
 * setting the system already had, so this update cannot silently clear anything
 * else the scene was carrying. A nil transition context is the ordinary private
 * call shape and lets the system build its own; no animation is requested, so
 * the application sees the new rectangle at once instead of at the end of a
 * transition it would have to be told to run. */
static BOOL sthApplyFrame(id scene, CGRect frame) {
  if (!scene) return NO;
  @try {
    if (![scene respondsToSelector:@selector(settings)] ||
        ![scene respondsToSelector:@selector(updateSettings:withTransitionContext:completion:)])
      return NO;
    id settings = [scene settings];
    if (!settings || ![settings respondsToSelector:@selector(mutableCopy)]) return NO;
    id mutable = [settings mutableCopy];
    if (!mutable || ![mutable respondsToSelector:@selector(setFrame:)]) return NO;
    [mutable setFrame:frame];
    [scene updateSettings:mutable withTransitionContext:nil completion:nil];
    return YES;
  } @catch (NSException *exception) {
    return NO;
  }
}

/* One entry per application identifier. The original frame is read once, from
 * the scene the application had before the first push, and every ratio is
 * derived from it, so repeated pushes are idempotent and a restore always has
 * the right target even after several ratio changes. */
static NSMutableDictionary<NSString *, NSMutableDictionary *> *sthEntries;

void STHScenePushViewport(NSString *bundle, STHVRect card, STHVRect screen) {
  if (!NSThread.isMainThread || !bundle.length) return;
  if (!STHVValid(card) || !STHVValid(screen)) return;
  // A card that covers the screen is not a card: the application is native and
  // whatever frame it had must come back.
  if (card.w >= screen.w - 1.0 && card.h >= screen.h - 1.0) {
    STHScenePushRestore(bundle);
    return;
  }
  double now = NSProcessInfo.processInfo.systemUptime;
  if (!sthEntries) sthEntries = [NSMutableDictionary new];
  NSMutableDictionary *entry = sthEntries[bundle];
  if (!entry) {
    entry = [NSMutableDictionary new];
    sthEntries[bundle] = entry;
  }
  if ([entry[@"retryAt"] doubleValue] > now) return;
  id scene = sthSceneFor(bundle);
  if (!scene) {
    entry[@"retryAt"] = @(now + 2.0);
    if (STHVDiagnosticsEnabled())
      STHVLog(@"sb-scene-miss", bundle, @{@"card": STHVRectJSON(card), @"screen": STHVRectJSON(screen)});
    return;
  }
  CGRect original;
  if (sthLoadRect(entry, @"original", &original)) {
    // Already read once, before the first push.
  } else {
    if (![scene respondsToSelector:@selector(settings)]) return;
    id settings = sthSettings(scene);
    if (!settings || ![settings respondsToSelector:@selector(frame)]) return;
    original = [settings frame];
    if (!isfinite(original.size.width) || !isfinite(original.size.height) ||
        original.size.width < 80.0 || original.size.height < 80.0)
      return;
    sthStoreRect(entry, @"original", original);
    if (STHVDiagnosticsEnabled())
      STHVLog(@"sb-scene-origin", bundle, @{@"frame": STHVRectJSON(sthVRect(original))});
  }
  CGFloat scaleX = card.w / screen.w, scaleY = card.h / screen.h;
  if (!isfinite(scaleX) || !isfinite(scaleY) || scaleX <= 0.0 || scaleY <= 0.0) return;
  // The scene frame is mapped from the rectangle the application had, not
  // computed from the card alone: a scene that is already inset keeps its own
  // inset relative to the new viewport, and a full screen scene becomes exactly
  // the card.
  CGRect target;
  target.origin.x = card.x + (original.origin.x - screen.x) * scaleX;
  target.origin.y = card.y + (original.origin.y - screen.y) * scaleY;
  target.size.width = original.size.width * scaleX;
  target.size.height = original.size.height * scaleY;
  if (target.size.width < 80.0 || target.size.height < 80.0) return;
  // The frame the scene carries right now decides, not a remembered one. A
  // scene whose update was dropped, or which the system reverted when the
  // application was relaunched, must be written again on the next beat; a
  // remembered target alone would leave it at whatever the system chose.
  id settings = sthSettings(scene);
  if (!settings || ![settings respondsToSelector:@selector(frame)]) return;
  CGRect current = [settings frame];
  if (sthSameRect(current, target)) {
    sthStoreRect(entry, @"applied", target);
    return;
  }
  if (!sthApplyFrame(scene, target)) {
    entry[@"retryAt"] = @(now + 2.0);
    if (STHVDiagnosticsEnabled())
      STHVLog(@"sb-scene-refused", bundle,
              @{@"before": STHVRectJSON(sthVRect(original)), @"target": STHVRectJSON(sthVRect(target)),
                @"card": STHVRectJSON(card), @"screen": STHVRectJSON(screen)});
    return;
  }
  sthStoreRect(entry, @"applied", target);
  entry[@"retryAt"] = @0;
  if (STHVDiagnosticsEnabled())
    STHVLog(@"sb-scene-push", bundle,
            @{@"before": STHVRectJSON(sthVRect(original)), @"target": STHVRectJSON(sthVRect(target)),
              @"card": STHVRectJSON(card), @"screen": STHVRectJSON(screen)});
}

void STHScenePushRestore(NSString *bundle) {
  if (!NSThread.isMainThread || !bundle.length || !sthEntries) return;
  NSMutableDictionary *entry = sthEntries[bundle];
  if (!entry) return;
  CGRect original;
  // No push ever happened for this application: nothing to put back.
  if (!sthLoadRect(entry, @"original", &original) || !entry[@"applied"]) return;
  id scene = sthSceneFor(bundle);
  // The application may be gone already. The record is kept so a later launch
  // of the same identifier still restores the frame it was given, instead of
  // inheriting a carded rectangle it never asked for.
  if (!scene) return;
  if (!sthApplyFrame(scene, original)) return;
  if (STHVDiagnosticsEnabled())
    STHVLog(@"sb-scene-restore", bundle, @{@"frame": STHVRectJSON(sthVRect(original))});
  [sthEntries removeObjectForKey:bundle];
}
