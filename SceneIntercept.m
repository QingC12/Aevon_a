// Give a carded application the card as its own scene rectangle.
//
// The approaches that only answer a getter all end at the same wall: a page that
// was prepared while the card was still moving keeps the width it sampled and
// never asks again, so a later answer cannot repair it and marking views dirty
// does not either. Only a real change of the scene rectangle makes UIKit run a
// size transition, and that transition is what rebuilds those pages.
//
// This is the mechanism the original uses from springboard: the settings a scene
// is about to receive are intercepted and their frame rewritten, and the new
// rectangle is pushed at once when the card changes, so a ratio change takes
// effect immediately instead of waiting for the system to have something to say.
//
// Nothing here is linked and no private header is imported. The classes are
// resolved by name, the few messages used are declared on NSObject below, and
// every send is behind respondsToSelector: a wrong guess must be a no-op, never a
// springboard crash.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <stdlib.h>
#import "SceneIntercept.h"
#import "SceneInterceptPolicy.h"
#import "ViewportDiagnostics.h"

@interface NSObject (STHSceneInterceptPrivate)
+ (id)sharedInstance;
- (id)settings;
- (CGRect)frame;
- (void)setFrame:(CGRect)frame;
- (void)updateSettings:(id)settings
    withTransitionContext:(id)context
              completion:(id)completion;
- (id)mainScene;
- (id)scenes;
- (id)scene;
- (id)allScenes;
- (id)sceneWithIdentifier:(NSString *)identifier;
- (id)identifier;
- (id)clientProcess;
- (id)bundleIdentifier;
- (id)applicationWithBundleIdentifier:(NSString *)identifier;
@end

typedef id (*STHInterceptIMP)(id, SEL, id, id);
typedef void (*STHUpdateIMP)(id, SEL, id, id, id);

static NSMutableDictionary<NSString *, NSMutableDictionary *> *sthRecords;
static BOOL sthInstallTried;
static Class sthManagerClass, sthSceneClass;
static IMP sthManagerOriginal, sthSceneUpdateOriginal;

/* One entry per application identifier: the card, the screen it was measured
 * against, the frame the application had before the first push, and whether a
 * card is open. The original frame is captured once, so repeated ratio changes
 * map from the same rectangle instead of compounding. */
static STHSIRect sthIn(STHVRect r) { return (STHSIRect){r.x, r.y, r.w, r.h}; }
static STHVRect sthOut(STHSIRect r) { return (STHVRect){r.x, r.y, r.w, r.h}; }
static STHVRect sthFromCGRect(CGRect r) {
  return (STHVRect){r.origin.x, r.origin.y, r.size.width, r.size.height};
}
static id sthBox(STHVRect r) { return @[ @(r.x), @(r.y), @(r.w), @(r.h) ]; }
static BOOL sthUnbox(id value, STHVRect *rect) {
  if (![value isKindOfClass:NSArray.class]) return NO;
  NSArray *parts = (NSArray *)value;
  if (parts.count != 4) return NO;
  if (rect)
    *rect = (STHVRect){[parts[0] doubleValue], [parts[1] doubleValue],
                       [parts[2] doubleValue], [parts[3] doubleValue]};
  return YES;
}
/* Every send to a system object is declared above and guarded here. These
 * objects are private, their shape differs between releases, and a message this
 * build does not know how to send must be dropped. */
static id sthShared(NSString *className) {
  Class cls = NSClassFromString(className);
  if (!cls || ![cls respondsToSelector:@selector(sharedInstance)]) return nil;
  return [(id)cls sharedInstance];
}
static id sthIdentifier(id object) {
  return [object respondsToSelector:@selector(identifier)] ? [object identifier] : nil;
}
static id sthClientProcess(id object) {
  return [object respondsToSelector:@selector(clientProcess)] ? [object clientProcess] : nil;
}
static id sthProcessBundle(id process) {
  return [process respondsToSelector:@selector(bundleIdentifier)] ? [process bundleIdentifier] : nil;
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
static id sthSettingsOf(id scene) {
  return [scene respondsToSelector:@selector(settings)] ? [scene settings] : nil;
}
static id sthSceneByIdentifier(id manager, NSString *bundle) {
  return [manager respondsToSelector:@selector(sceneWithIdentifier:)]
             ? [manager sceneWithIdentifier:bundle]
             : nil;
}
/* Only an object that carries settings is a scene; some releases hand back a
 * handle that wraps one. */
static id sthUnwrap(id candidate) {
  if (!candidate) return nil;
  if ([candidate respondsToSelector:@selector(settings)]) return candidate;
  id inner = sthWrappedScene(candidate);
  return (inner && [inner respondsToSelector:@selector(settings)]) ? inner : nil;
}
static id sthSceneFor(NSString *bundle) {
  id controller = sthShared(@"SBApplicationController");
  id application = nil;
  if ([controller respondsToSelector:@selector(applicationWithBundleIdentifier:)])
    application = [controller applicationWithBundleIdentifier:bundle];
  if (application) {
    id scene = sthUnwrap(sthMainScene(application));
    if (scene) return scene;
    id scenes = sthScenes(application);
    if ([scenes isKindOfClass:NSArray.class] || [scenes isKindOfClass:NSSet.class])
      for (id candidate in (id)scenes) {
        scene = sthUnwrap(candidate);
        if (scene) return scene;
      }
  }
  id manager = sthShared(@"FBSceneManager");
  id byIdentifier = sthUnwrap(sthSceneByIdentifier(manager, bundle));
  if (byIdentifier) return byIdentifier;
  id all = sthAllScenes(manager);
  if (![all isKindOfClass:NSArray.class] && ![all isKindOfClass:NSSet.class]) return nil;
  for (id candidate in all) {
    if (![sthIdentifier(candidate) isKindOfClass:NSString.class]) continue;
    if (![sthIdentifier(candidate) isEqual:bundle]) continue;
    id scene = sthUnwrap(candidate);
    if (scene) return scene;
  }
  return nil;
}
/* The identifier of an application scene is its bundle identifier, sometimes
 * with a suffix for an extra scene, so a prefix match is the same answer the
 * direct lookup would have given. */
static NSString *sthBundleForScene(id scene) {
  if (!scene || !sthRecords.count) return nil;
  id identifier = sthIdentifier(scene);
  if ([identifier isKindOfClass:NSString.class]) {
    if (sthRecords[identifier]) return identifier;
    for (NSString *bundle in sthRecords)
      if ([(NSString *)identifier hasPrefix:bundle]) return bundle;
  }
  NSString *fromProcess = sthProcessBundle(sthClientProcess(scene));
  if ([fromProcess isKindOfClass:NSString.class] && sthRecords[fromProcess]) return fromProcess;
  return nil;
}
static STHVRect sthCurrentFrame(id scene) {
  id settings = sthSettingsOf(scene);
  if (!settings || ![settings respondsToSelector:@selector(frame)]) return (STHVRect){0};
  return sthFromCGRect([settings frame]);
}
/* The frame the application had before this module wrote anything. A scene that
 * is already much smaller than the screen is one this module resized earlier, so
 * the screen is the honest original rather than that leftover rectangle. */
static STHVRect sthOriginalFrame(STHVRect current, STHVRect screen) {
  if (!STHVValid(current)) return screen;
  if (STHVNear(current, screen, 1.0)) return screen;
  if (current.w < screen.w - 8.0 || current.h < screen.h - 8.0) return screen;
  return current;
}
/* Only the frame is written. The mutable copy carries every other setting the
 * system already had, so this update cannot silently clear anything else. */
static BOOL sthWriteFrame(id scene, STHVRect target, NSString *event, NSString *bundle,
                          STHVRect card, STHVRect screen) {
  id settings = sthSettingsOf(scene);
  if (!settings || ![settings respondsToSelector:@selector(mutableCopy)]) return NO;
  id mutable = [settings mutableCopy];
  if (!mutable || ![mutable respondsToSelector:@selector(setFrame:)]) return NO;
  [mutable setFrame:CGRectMake(target.x, target.y, target.w, target.h)];
  if (![scene respondsToSelector:@selector(updateSettings:withTransitionContext:completion:)])
    return NO;
  [scene updateSettings:mutable withTransitionContext:nil completion:nil];
  if (STHVDiagnosticsEnabled())
    STHVLog(event, bundle, @{@"frame": STHVRectJSON(target), @"card": STHVRectJSON(card),
                             @"screen": STHVRectJSON(screen)});
  return YES;
}
/* The rectangle the scene should carry right now: the card while it is open, the
 * application's own rectangle once it is gone. Zero means "leave the scene
 * alone" - an unreadable record, or a card that is the whole screen. */
static STHVRect sthTargetFor(NSMutableDictionary *record, BOOL *active) {
  STHVRect card = {0}, screen = {0}, original = {0};
  if (!sthUnbox(record[@"card"], &card) || !sthUnbox(record[@"screen"], &screen))
    return (STHVRect){0};
  if (!sthUnbox(record[@"original"], &original)) original = screen;
  BOOL open = [record[@"active"] boolValue];
  if (active) *active = open;
  if (!open) return original;
  if (STHSICardIsScreen(sthIn(card), sthIn(screen))) return original;
  STHSIRect mapped = {0};
  if (!STHSIMapTarget(sthIn(card), sthIn(screen), sthIn(original), &mapped))
    return (STHVRect){0};
  return sthOut(mapped);
}
/* The settings about to be handed to the scene. Only a tracked application is
 * touched, and only when the frame really differs, so an untouched scene costs
 * one comparison. */
static id sthRewriteFrame(id scene, id settings) {
  if (!settings || ![settings respondsToSelector:@selector(frame)]) return settings;
  NSString *bundle = sthBundleForScene(scene);
  if (!bundle) return settings;
  NSMutableDictionary *record = sthRecords[bundle];
  if (!record) return settings;
  BOOL active = NO;
  STHVRect target = sthTargetFor(record, &active);
  if (!STHVValid(target)) return settings;
  STHVRect current = sthFromCGRect([settings frame]);
  if (STHVNear(current, target, 0.5)) {
    // Restore is complete once the scene carries its own rectangle again.
    if (!active) [sthRecords removeObjectForKey:bundle];
    return settings;
  }
  id mutable = [settings mutableCopy];
  if (!mutable || ![mutable respondsToSelector:@selector(setFrame:)]) return settings;
  [mutable setFrame:CGRectMake(target.x, target.y, target.w, target.h)];
  if (STHVDiagnosticsEnabled()) {
    STHVRect card = {0}, screen = {0};
    sthUnbox(record[@"card"], &card);
    sthUnbox(record[@"screen"], &screen);
    STHVLog(@"sb-scene-intercepted", bundle,
            @{@"active": @(active), @"from": STHVRectJSON(current), @"to": STHVRectJSON(target),
              @"card": STHVRectJSON(card), @"screen": STHVRectJSON(screen)});
  }
  return mutable;
}
static IMP sthOriginalFor(id self, Class owner, IMP original) {
  Class cls = object_getClass(self);
  for (Class walk = cls; walk; walk = class_getSuperclass(walk))
    if (walk == owner) return original;
  return NULL;
}
static id sthInterceptTrampoline(id self, SEL command, id scene, id settings) {
  IMP original = sthOriginalFor(self, sthManagerClass, sthManagerOriginal);
  id returned = original ? ((STHInterceptIMP)original)(self, command, scene, settings) : settings;
  @try {
    return sthRewriteFrame(scene, returned ?: settings);
  } @catch (NSException *exception) {
    return returned ?: settings;
  }
}
static void sthUpdateTrampoline(id self, SEL command, id settings, id context, id completion) {
  IMP original = sthOriginalFor(self, sthSceneClass, sthSceneUpdateOriginal);
  id rewritten = settings;
  @try {
    rewritten = sthRewriteFrame(self, settings);
  } @catch (NSException *exception) {
  }
  if (original) ((STHUpdateIMP)original)(self, command, rewritten, context, completion);
}
/* One class per method shape. The method is replaced on the class that defines
 * it, and the original is only used for instances below that class, so ordinary
 * scene updates outside the card path are untouched. */
static BOOL sthHook(Class cls, SEL selector, IMP replacement, Class *owner, IMP *original) {
  if (!cls || !selector) return NO;
  Method method = class_getInstanceMethod(cls, selector);
  if (!method) return NO;
  IMP current = method_getImplementation(method);
  if (current == replacement) return NO;
  unsigned int count = 0;
  Method *list = class_copyMethodList(cls, &count);
  BOOL defined = NO;
  for (unsigned int i = 0; i < count && !defined; i++) defined = method_getName(list[i]) == selector;
  free(list);
  // An inherited method is hooked on the class that defines it, which is where
  // the candidate list would have found it too.
  if (!defined) {
    Class super = class_getSuperclass(cls);
    return sthHook(super, selector, replacement, owner, original);
  }
  *owner = cls;
  *original = current;
  method_setImplementation(method, replacement);
  return YES;
}
static void sthInstall(void) {
  if (sthInstallTried) return;
  sthInstallTried = YES;
  SEL intercept = NSSelectorFromString(@"_scene:interceptUpdateWithNewSettings:");
  static const char *managers[] = {"SBMainDisplaySceneManager", "SBSceneManager", "FBSceneManager"};
  for (unsigned int i = 0; i < sizeof(managers) / sizeof(managers[0]) && !sthManagerClass; i++)
    sthHook(NSClassFromString([NSString stringWithUTF8String:managers[i]]), intercept,
            (IMP)sthInterceptTrampoline, &sthManagerClass, &sthManagerOriginal);
  // The push a ratio change makes goes through the scene itself, so the same
  // rewrite has to sit on the application side of that message as well.
  SEL update = NSSelectorFromString(@"updateSettings:withTransitionContext:completion:");
  if (!sthSceneClass)
    sthHook(NSClassFromString(@"FBScene"), update, (IMP)sthUpdateTrampoline, &sthSceneClass,
            &sthSceneUpdateOriginal);
  if (STHVDiagnosticsEnabled())
    STHVLog(@"sb-scene-hook", @"com.apple.springboard",
            @{@"intercept": @(sthManagerClass != nil), @"update": @(sthSceneClass != nil)});
}
static NSMutableDictionary *sthRecord(NSString *bundle, BOOL create) {
  if (!bundle.length) return nil;
  if (!sthRecords) sthRecords = [NSMutableDictionary new];
  NSMutableDictionary *record = sthRecords[bundle];
  if (!record && create) {
    record = [NSMutableDictionary new];
    sthRecords[bundle] = record;
  }
  return record;
}

void STHSceneInterceptTrack(NSString *bundle, STHVRect card, STHVRect screen) {
  if (!NSThread.isMainThread || !bundle.length) return;
  if (!STHVValid(card) || !STHVValid(screen)) return;
  if (card.w < 80.0 || card.h < 80.0 || screen.w < 80.0 || screen.h < 80.0) return;
  sthInstall();
  id scene = sthSceneFor(bundle);
  NSMutableDictionary *record = sthRecord(bundle, YES);
  STHVRect previous = {0};
  BOOL had = sthUnbox(record[@"card"], &previous);
  record[@"card"] = sthBox(card);
  record[@"screen"] = sthBox(screen);
  record[@"active"] = @YES;
  STHVRect original = {0};
  if (!sthUnbox(record[@"original"], &original)) {
    original = sthOriginalFrame(sthCurrentFrame(scene), screen);
    record[@"original"] = sthBox(original);
  }
  // Nothing to write for a card that is the whole screen, and nothing to write
  // twice for a card that did not move since the last beat.
  if (STHSICardIsScreen(sthIn(card), sthIn(screen))) return;
  if (had && STHVNear(previous, card, 0.5)) return;
  if (!scene) return;
  STHVRect target = {0};
  STHSIRect mapped = {0};
  if (!STHSIMapTarget(sthIn(card), sthIn(screen), sthIn(original), &mapped)) return;
  target = sthOut(mapped);
  if (STHVNear(sthCurrentFrame(scene), target, 0.5)) return;
  sthWriteFrame(scene, target, @"sb-scene-push", bundle, card, screen);
}

void STHSceneInterceptUntrack(NSString *bundle) {
  if (!NSThread.isMainThread || !bundle.length || !sthRecords) return;
  NSMutableDictionary *record = sthRecords[bundle];
  if (!record) return;
  record[@"active"] = @NO;
  STHVRect screen = {0}, original = {0};
  if (!sthUnbox(record[@"screen"], &screen)) {
    [sthRecords removeObjectForKey:bundle];
    return;
  }
  if (!sthUnbox(record[@"original"], &original) || !STHVValid(original)) original = screen;
  id scene = sthSceneFor(bundle);
  if (!scene) {
    // The application is gone. The record is kept so a later launch of the same
    // identifier is still put back on its own rectangle.
    return;
  }
  // The system may not invent an update just because a card closed, so the
  // restore is written now. The record stays until an update is seen carrying
  // its own rectangle, so a dropped write is corrected by the next one.
  if (!sthWriteFrame(scene, original, @"sb-scene-restore", bundle, (STHVRect){0}, screen)) return;
  if (STHVNear(sthCurrentFrame(scene), original, 0.5)) [sthRecords removeObjectForKey:bundle];
}
