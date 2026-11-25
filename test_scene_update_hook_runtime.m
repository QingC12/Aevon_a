/* The scene update hook driven through a stand-in springboard: a fake scene
 * manager with the private interception selector, a fake scene that keeps its
 * settings, and a fake settings object that carries one frame. No FrontBoard, no
 * device, no timer. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <assert.h>
#import "SceneUpdateHook.m"

// The recorder is compiled out of this build, but the module still names it from
// a branch that can never run.
void STHVLog(NSString *event, NSString *bundle, NSDictionary *values) {
  (void)event;(void)bundle;(void)values;
}
NSDictionary *STHVRectJSON(STHVRect rect) {
  return @{@"x": @(rect.x), @"y": @(rect.y), @"w": @(rect.w), @"h": @(rect.h)};
}

@interface FakeSettings : NSObject <NSCopying, NSMutableCopying>
@property CGRect frame;
@end
@implementation FakeSettings
- (id)copyWithZone:(NSZone *)zone {
  FakeSettings *copy = [FakeSettings new];
  copy.frame = _frame;
  return copy;
}
- (id)mutableCopyWithZone:(NSZone *)zone { return [self copyWithZone:zone]; }
@end

@interface FakeScene : NSObject
@property(copy) NSString *identifier;
@property(strong) FakeSettings *settings;
@property(assign) NSUInteger pushes;
@end
@implementation FakeScene
- (void)updateSettings:(id)settings
    withTransitionContext:(id)context
              completion:(id)completion {
  (void)context;(void)completion;
  _pushes++;
  _settings = [settings copy];
}
@end

@interface FakeApplication : NSObject
@property(strong) FakeScene *mainScene;
@end
@implementation FakeApplication
@end

@interface SBApplicationController : NSObject
@property(strong) NSMutableDictionary<NSString *, FakeApplication *> *applications;
+ (SBApplicationController *)sharedInstance;
@end
@implementation SBApplicationController
+ (SBApplicationController *)sharedInstance {
  static SBApplicationController *shared;
  if (!shared) shared = [SBApplicationController new];
  return shared;
}
- (id)applicationWithBundleIdentifier:(NSString *)identifier {
  return _applications[identifier];
}
@end

@interface SBMainDisplaySceneManager : NSObject
- (id)_scene:(id)scene interceptUpdateWithNewSettings:(id)settings;
@end
@implementation SBMainDisplaySceneManager
- (id)_scene:(id)scene interceptUpdateWithNewSettings:(id)settings { return settings; }
@end

static CGRect frameOf(id settings) { return [settings frame]; }
static BOOL same(CGRect a, CGRect b) {
  return fabs(a.origin.x - b.origin.x) < 0.5 && fabs(a.origin.y - b.origin.y) < 0.5 &&
         fabs(a.size.width - b.size.width) < 0.5 && fabs(a.size.height - b.size.height) < 0.5;
}
static FakeSettings *settingsAt(CGRect frame) {
  FakeSettings *settings = [FakeSettings new];
  settings.frame = frame;
  return settings;
}

int main(void) {
  @autoreleasepool {
    NSString *bundle = @"com.example.feed";
    // The scene keeps an origin of its own. Only the size may ever change, so
    // that origin is the witness that the origin is not being rewritten.
    CGRect screen = CGRectMake(0, 20, 430, 932);
    FakeScene *scene = [FakeScene new];
    scene.identifier = bundle;
    scene.settings = settingsAt(screen);
    FakeApplication *application = [FakeApplication new];
    application.mainScene = scene;
    [SBApplicationController sharedInstance].applications = [@{bundle: application} mutableCopy];
    SBMainDisplaySceneManager *manager = [SBMainDisplaySceneManager new];
    STHVRect screenRect = {0, 20, 430, 932};

    // An application the host is not tracking is never touched, at the
    // interception point or anywhere else.
    FakeSettings *plain = settingsAt(screen);
    assert([manager _scene:scene interceptUpdateWithNewSettings:plain] == plain);

    // A card is pushed as the scene size at once, and the origin the scene
    // carried survives it.
    STHVRect card = {0, 120.5, 430, 731};
    STHSceneUpdateHookTrack(bundle, card, screenRect);
    assert(scene.pushes == 1);
    assert(same(frameOf(scene.settings), CGRectMake(0, 20, 430, 731)));

    // The same card seen again on the next beat writes nothing.
    NSUInteger pushes = scene.pushes;
    STHSceneUpdateHookTrack(bundle, card, screenRect);
    assert(scene.pushes == pushes);

    // The system sends the full screen size; the interception turns it into the
    // card size and keeps the origin of the settings it was handed.
    FakeSettings *full = settingsAt(CGRectMake(0, 20, 430, 932));
    id returned = [manager _scene:scene interceptUpdateWithNewSettings:full];
    assert(returned != full);
    assert(same(frameOf(returned), CGRectMake(0, 20, 430, 731)));
    assert(scene.pushes == pushes);

    // A settings object that already carries the card size is passed through
    // unchanged, so an untouched scene costs one comparison.
    FakeSettings *already = settingsAt(CGRectMake(0, 20, 430, 731));
    assert([manager _scene:scene interceptUpdateWithNewSettings:already] == already);

    // A second ratio changes the size again, not by compounding.
    STHVRect narrow = {0, 150, 300, 650};
    STHSceneUpdateHookTrack(bundle, narrow, screenRect);
    assert(same(frameOf(scene.settings), CGRectMake(0, 20, 300, 650)));
    FakeSettings *narrowSettings = settingsAt(CGRectMake(0, 20, 430, 932));
    assert(same(frameOf([manager _scene:scene interceptUpdateWithNewSettings:narrowSettings]),
                CGRectMake(0, 20, 300, 650)));

    // A card that covers the screen is native: the application is put back on
    // the screen size and the record is finished.
    pushes = scene.pushes;
    STHSceneUpdateHookTrack(bundle, screenRect, screenRect);
    assert(scene.pushes == pushes + 1);
    assert(same(frameOf(scene.settings), CGRectMake(0, 20, 430, 932)));
    FakeSettings *afterFull = settingsAt(CGRectMake(0, 20, 300, 650));
    assert([manager _scene:scene interceptUpdateWithNewSettings:afterFull] == afterFull);

    // Closing a card restores the screen size as well.
    STHSceneUpdateHookTrack(bundle, narrow, screenRect);
    assert(same(frameOf(scene.settings), CGRectMake(0, 20, 300, 650)));
    pushes = scene.pushes;
    STHSceneUpdateHookUntrack(bundle);
    assert(scene.pushes == pushes + 1);
    assert(same(frameOf(scene.settings), CGRectMake(0, 20, 430, 932)));

    // A foreign application is never rewritten, and an unreadable card or an
    // empty identifier is never tracked.
    FakeScene *other = [FakeScene new];
    other.identifier = @"com.example.other";
    other.settings = settingsAt(screen);
    FakeSettings *foreign = settingsAt(screen);
    assert([manager _scene:other interceptUpdateWithNewSettings:foreign] == foreign);
    STHSceneUpdateHookTrack(bundle, (STHVRect){0, 0, 0, 0}, screenRect);
    STHSceneUpdateHookTrack(bundle, narrow, (STHVRect){0, 0, 0, 0});
    STHSceneUpdateHookTrack(@"", narrow, screenRect);
    STHSceneUpdateHookUntrack(@"");
    assert(same(frameOf(scene.settings), CGRectMake(0, 20, 430, 932)));
  }
  puts("Scene update hook: the card is the scene size on the first pass; the origin is never "
       "touched; a repeated card and an already correct settings write nothing; a second ratio "
       "resizes again; a full screen card and a closed card both restore the screen size; a "
       "foreign application is untouched");
  return 0;
}
