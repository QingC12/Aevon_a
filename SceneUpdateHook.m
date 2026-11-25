// Put the private scene update hooks back.
//
// The port dropped them and answered UIScreen.bounds instead. A getter answer
// reaches an application that is asking; it cannot reach one that already laid
// itself out. The scene hooks do reach it, because they change the settings the
// system is about to apply, and UIKit turns that into a real size transition:
// the application's window becomes the card, and every page laid out inside it
// is rebuilt. That is the mechanism the original uses, and it is the only one
// that repairs a page which stopped asking.
//
// Only the size is written. The origin of the frame the system sent, the level,
// the interface orientation and every other setting stay as they are, so this
// cannot change anything except how wide and how tall the application believes
// it is.
//
// Nothing here is linked and no private header is imported: the classes are
// resolved by name, the few messages used are declared on NSObject below, and
// every send is behind respondsToSelector, so a wrong guess is a no-op rather
// than a springboard crash.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <stdlib.h>

#import "SceneUpdateHook.h"
#import "ViewportDiagnostics.h"

@interface NSObject (STHSceneUpdatePrivate)
+ (id)sharedInstance;
- (id)settings;
- (CGRect)frame;
- (void)setFrame:(CGRect)frame;
- (id)mutableCopy;
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

typedef id (*STHSceneInterceptIMP)(id, SEL, id, id);
typedef void (*STHSceneUpdateIMP)(id, SEL, id, id, id);

static NSMutableDictionary<NSString *, NSMutableDictionary *> *sceneRecords;
static BOOL sceneHookTried;
static Class sceneManagerClass, sceneObjectClass;
static IMP sceneManagerOriginal, sceneObjectUpdateOriginal;

static void sthSizeStore(NSMutableDictionary *record, double width, double height) {
  record[@"w"] = @(width);
  record[@"h"] = @(height);
}
static id sthShared(NSString *className) {
  Class cls = NSClassFromString(className);
  if (!cls || ![cls respondsToSelector:@selector(sharedInstance)]) return nil;
  return [(id)cls sharedInstance];
}
static id sthSettingsOf(id scene) {
  return [scene respondsToSelector:@selector(settings)] ? [scene settings] : nil;
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
static id sthSceneByIdentifier(id manager, NSString *bundle) {
  return [manager respondsToSelector:@selector(sceneWithIdentifier:)]
             ? [manager sceneWithIdentifier:bundle]
             : nil;
}
// A scene is the object that carries settings. Some releases hand back a handle
// that wraps one, so the wrapper is unwrapped before it is used.
static id sthUnwrap(id candidate) {
  if (!candidate) return nil;
  if ([candidate respondsToSelector:@selector(settings)]) return candidate;
  id inner = sthWrappedScene(candidate);
  return (inner && [inner respondsToSelector:@selector(settings)]) ? inner : nil;
}
static id sthSceneFor(NSString *bundle) {
  id controller = sthShared(@"SBApplicationController");
  if ([controller respondsToSelector:@selector(applicationWithBundleIdentifier:)]) {
    id application = [controller applicationWithBundleIdentifier:bundle];
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
  }
  id manager = sthShared(@"FBSceneManager");
  id byIdentifier = sthUnwrap(sthSceneByIdentifier(manager, bundle));
  if (byIdentifier) return byIdentifier;
  id all = sthAllScenes(manager);
  if (![all isKindOfClass:NSArray.class] && ![all isKindOfClass:NSSet.class]) return nil;
  for (id candidate in all) {
    id identifier = sthIdentifier(candidate);
    if (![identifier isKindOfClass:NSString.class] || ![identifier isEqual:bundle]) continue;
    id scene = sthUnwrap(candidate);
    if (scene) return scene;
  }
  return nil;
}
// A scene identifier is the bundle identifier, sometimes with a suffix for an
// extra scene, so a prefix match is the same answer the direct lookup gives.
static NSString *sthBundleForScene(id scene) {
  if (!scene || !sceneRecords.count) return nil;
  id identifier = sthIdentifier(scene);
  if ([identifier isKindOfClass:NSString.class]) {
    if (sceneRecords[identifier]) return identifier;
    for (NSString *bundle in sceneRecords)
      if ([(NSString *)identifier hasPrefix:bundle]) return bundle;
  }
  id fromProcess = sthProcessBundle(sthClientProcess(scene));
  if ([fromProcess isKindOfClass:NSString.class] && sceneRecords[fromProcess]) return fromProcess;
  return nil;
}
static BOOL sthCurrentSize(id scene, double *width, double *height) {
  id settings = sthSettingsOf(scene);
  if (!settings || ![settings respondsToSelector:@selector(frame)]) return NO;
  CGRect frame = [settings frame];
  if (width) *width = frame.size.width;
  if (height) *height = frame.size.height;
  return YES;
}
// The settings the scene is about to receive, with the size of the card the
// application is shown in. The origin is the one the system sent.
static id sthRewriteSize(id scene, id settings) {
  if (!settings || ![settings respondsToSelector:@selector(frame)] ||
      ![settings respondsToSelector:@selector(mutableCopy)])
    return settings;
  NSString *bundle = sthBundleForScene(scene);
  if (!bundle) return settings;
  NSMutableDictionary *record = sceneRecords[bundle];
  if (!record) return settings;
  double width = [record[@"w"] doubleValue], height = [record[@"h"] doubleValue];
  if (width < 80.0 || height < 80.0) return settings;
  CGRect frame = [settings frame];
  if (fabs(frame.size.width - width) < 0.5 && fabs(frame.size.height - height) < 0.5)
    return settings;
  id mutable = [settings mutableCopy];
  if (!mutable || ![mutable respondsToSelector:@selector(setFrame:)]) return settings;
  [mutable setFrame:CGRectMake(frame.origin.x, frame.origin.y, width, height)];
  if (STHVDiagnosticsEnabled())
    STHVLog(@"sb-scene-size", bundle,
            @{@"from": @[@(frame.size.width), @(frame.size.height)],
              @"to": @[@(width), @(height)]});
  return mutable;
}
// The original implementation is only used for instances of the class that does
// not define the selector itself, which is what the owner walk establishes.
static IMP sthOriginalFor(id self, Class owner, IMP original) {
  for (Class walk = object_getClass(self); walk; walk = class_getSuperclass(walk))
    if (walk == owner) return original;
  return NULL;
}
static id sthInterceptTrampoline(id self, SEL command, id scene, id settings) {
  IMP original = sthOriginalFor(self, sceneManagerClass, sceneManagerOriginal);
  id returned = original ? ((STHSceneInterceptIMP)original)(self, command, scene, settings)
                         : settings;
  @try {
    return sthRewriteSize(scene, returned ?: settings);
  } @catch (NSException *exception) {
    return returned ?: settings;
  }
}
static void sthUpdateTrampoline(id self, SEL command, id settings, id context, id completion) {
  IMP original = sthOriginalFor(self, sceneObjectClass, sceneObjectUpdateOriginal);
  id rewritten = settings;
  @try {
    rewritten = sthRewriteSize(self, settings);
  } @catch (NSException *exception) {
  }
  if (original) ((STHSceneUpdateIMP)original)(self, command, rewritten, context, completion);
}
static BOOL sthHook(Class cls, SEL selector, IMP replacement, Class *owner, IMP *original) {
  if (!cls) return NO;
  Method method = class_getInstanceMethod(cls, selector);
  if (!method) return NO;
  IMP current = method_getImplementation(method);
  if (current == replacement) return NO;
  unsigned int count = 0;
  Method *list = class_copyMethodList(cls, &count);
  BOOL defined = NO;
  for (unsigned int i = 0; i < count && !defined; i++) defined = method_getName(list[i]) == selector;
  free(list);
  if (!defined) return sthHook(class_getSuperclass(cls), selector, replacement, owner, original);
  *owner = cls;
  *original = current;
  method_setImplementation(method, replacement);
  return YES;
}
static void sthInstall(void) {
  if (sceneHookTried) return;
  sceneHookTried = YES;
  SEL intercept = NSSelectorFromString(@"_scene:interceptUpdateWithNewSettings:");
  static const char *managers[] = {"SBMainDisplaySceneManager", "SBSceneManager", "FBSceneManager",
                                   "UIMainDisplaySceneManager"};
  for (unsigned int i = 0; i < sizeof(managers) / sizeof(managers[0]) && !sceneManagerClass; i++)
    sthHook(NSClassFromString([NSString stringWithUTF8String:managers[i]]), intercept,
            (IMP)sthInterceptTrampoline, &sceneManagerClass, &sceneManagerOriginal);
  SEL update = NSSelectorFromString(@"updateSettings:withTransitionContext:completion:");
  sthHook(NSClassFromString(@"FBScene"), update, (IMP)sthUpdateTrampoline, &sceneObjectClass,
          &sceneObjectUpdateOriginal);
  if (STHVDiagnosticsEnabled())
    STHVLog(@"sb-scene-hook", @"com.apple.springboard",
            @{@"intercept": @(sceneManagerClass != nil), @"update": @(sceneObjectClass != nil)});
}
static NSMutableDictionary *sthRecord(NSString *bundle, BOOL create) {
  if (!bundle.length) return nil;
  if (!sceneRecords) sceneRecords = [NSMutableDictionary new];
  NSMutableDictionary *record = sceneRecords[bundle];
  if (!record && create) {
    record = [NSMutableDictionary new];
    sceneRecords[bundle] = record;
  }
  return record;
}
static void sthWriteSize(id scene, double width, double height, NSString *event, NSString *bundle) {
  id settings = sthSettingsOf(scene);
  if (!settings || ![settings respondsToSelector:@selector(mutableCopy)]) return;
  id mutable = [settings mutableCopy];
  if (!mutable || ![mutable respondsToSelector:@selector(setFrame:)]) return;
  CGRect frame = [settings respondsToSelector:@selector(frame)] ? [settings frame] : CGRectZero;
  [mutable setFrame:CGRectMake(frame.origin.x, frame.origin.y, width, height)];
  if (![scene respondsToSelector:@selector(updateSettings:withTransitionContext:completion:)]) return;
  [scene updateSettings:mutable withTransitionContext:nil completion:nil];
  if (STHVDiagnosticsEnabled())
    STHVLog(event, bundle, @{@"to": @[@(width), @(height)]});
}

void STHSceneUpdateHookTrack(NSString *bundle, STHVRect card, STHVRect screen) {
  if (!NSThread.isMainThread || !bundle.length) return;
  if (!STHVValid(card) || !STHVValid(screen)) return;
  if (card.w < 80.0 || card.h < 80.0) return;
  // A card that covers the screen is not a card: the application keeps the
  // rectangle the system gives it, exactly as it did before this module existed.
  if (fabs(card.w - screen.w) < 1.0 && fabs(card.h - screen.h) < 1.0) {
    STHSceneUpdateHookUntrack(bundle);
    return;
  }
  sthInstall();
  NSMutableDictionary *record = sthRecord(bundle, YES);
  double previous = [record[@"w"] doubleValue];
  double previousHeight = [record[@"h"] doubleValue];
  BOOL changed = fabs(previous - card.w) > 0.5 || fabs(previousHeight - card.h) > 0.5;
  sthSizeStore(record, card.w, card.h);
  // The rectangle the application has when no card is around, kept so closing
  // the card can put the application back exactly where it came from.
  if (!record[@"sw"]) {
    record[@"sw"] = @(screen.w);
    record[@"sh"] = @(screen.h);
  }
  id scene = sthSceneFor(bundle);
  if (!scene) return;
  double width = 0.0, height = 0.0;
  if (!sthCurrentSize(scene, &width, &height)) return;
  if (fabs(width - card.w) < 0.5 && fabs(height - card.h) < 0.5) return;
  // The card changed, or the scene drifted back to a size the system chose. A
  // half second guard keeps a scene that keeps refusing from being hammered.
  double now = NSProcessInfo.processInfo.systemUptime;
  double last = [record[@"at"] doubleValue];
  if (!changed && now - last < 0.5) return;
  record[@"at"] = @(now);
  sthWriteSize(scene, card.w, card.h, @"sb-scene-push", bundle);
}

void STHSceneUpdateHookUntrack(NSString *bundle) {
  if (!NSThread.isMainThread || !bundle.length || !sceneRecords) return;
  NSMutableDictionary *record = sceneRecords[bundle];
  if (!record) return;
  double width = [record[@"sw"] doubleValue], height = [record[@"sh"] doubleValue];
  // The record is dropped first, so this write is the last thing this module
  // does for the application and no later update is forced back to a card.
  [sceneRecords removeObjectForKey:bundle];
  if (width < 80.0 || height < 80.0) return;
  id scene = sthSceneFor(bundle);
  if (!scene) return;
  double currentWidth = 0.0, currentHeight = 0.0;
  if (!sthCurrentSize(scene, &currentWidth, &currentHeight)) return;
  if (fabs(currentWidth - width) < 0.5 && fabs(currentHeight - height) < 0.5) return;
  sthWriteSize(scene, width, height, @"sb-scene-clear", bundle);
}
