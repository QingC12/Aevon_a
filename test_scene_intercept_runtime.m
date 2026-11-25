/* The scene interception driven through a stand-in springboard: a fake scene
 * manager with the private interception selector, a fake scene that keeps its
 * settings, and a fake settings object that boxes one frame. No FrontBoard, no
 * device, no timer. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <assert.h>
#import "SceneIntercept.m"

// The diagnostics recorder is compiled out of this build, but the module still
// names it from a branch that can never run.
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
- (id)mutableCopyWithZone:(NSZone *)zone {
  return [self copyWithZone:zone];
}
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
- (id)_scene:(id)scene interceptUpdateWithNewSettings:(id)settings {
  return settings;
}
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
    CGRect screen = CGRectMake(0, 0, 430, 932);
    FakeScene *scene = [FakeScene new];
    scene.identifier = bundle;
    scene.settings = settingsAt(screen);
    FakeApplication *application = [FakeApplication new];
    application.mainScene = scene;
    [SBApplicationController sharedInstance].applications =
        [@{bundle: application} mutableCopy];
    SBMainDisplaySceneManager *manager = [SBMainDisplaySceneManager new];
    STHVRect screenRect = {0, 0, 430, 932};

    // An untracked application is never touched, even at the interception point.
    FakeSettings *plain = settingsAt(screen);
    assert([manager _scene:scene interceptUpdateWithNewSettings:plain] == plain);

    // The first card is pushed at once: a ratio change cannot wait for the
    // system to have something to say.
    STHVRect card = {0, 100.5, 430, 731};
    STHSceneInterceptTrack(bundle, card, screenRect);
    assert(scene.pushes == 1);
    assert(same(frameOf(scene.settings), CGRectMake(0, 100.5, 430, 731)));

    // The same update seen again changes nothing: the target is computed from
    // the frame the application had, not from the carded frame it carries now.
    NSUInteger pushes = scene.pushes;
    FakeSettings *again = settingsAt(screen);
    id returned = [manager _scene:scene interceptUpdateWithNewSettings:again];
    assert(returned != again);
    assert(same(frameOf(returned), CGRectMake(0, 100.5, 430, 731)));
    assert(scene.pushes == pushes);
    FakeSettings *already = settingsAt(CGRectMake(0, 100.5, 430, 731));
    assert([manager _scene:scene interceptUpdateWithNewSettings:already] == already);

    // A second ratio maps from the same original rectangle, so the sizes do not
    // compound the way a card-in-card mapping would.
    STHVRect narrow = {0, 150, 300, 650};
    STHSceneInterceptTrack(bundle, narrow, screenRect);
    assert(same(frameOf(scene.settings), CGRectMake(0, 150, 300, 650)));
    FakeSettings *narrowed = settingsAt(screen);
    assert(same(frameOf([manager _scene:scene interceptUpdateWithNewSettings:narrowed]),
                CGRectMake(0, 150, 300, 650)));

    // A card that covers the screen is native: nothing is written.
    pushes = scene.pushes;
    STHSceneInterceptTrack(bundle, screenRect, screenRect);
    assert(scene.pushes == pushes);

    // Closing the card puts the application back on its own rectangle at once.
    STHSceneInterceptTrack(bundle, narrow, screenRect);
    pushes = scene.pushes;
    STHSceneInterceptUntrack(bundle);
    assert(scene.pushes == pushes + 1);
    assert(same(frameOf(scene.settings), screen));
    // Once the scene carries its own rectangle the record is finished, so an
    // ordinary later size change is not forced back to a remembered one.
    FakeSettings *settled = settingsAt(CGRectMake(0, 0, 400, 900));
    assert([manager _scene:scene interceptUpdateWithNewSettings:settled] == settled);

    // An application the record does not know is never rewritten, and an
    // unreadable card is never tracked.
    FakeScene *other = [FakeScene new];
    other.identifier = @"com.example.other";
    other.settings = settingsAt(screen);
    FakeSettings *foreign = settingsAt(screen);
    assert([manager _scene:other interceptUpdateWithNewSettings:foreign] == foreign);
    STHSceneInterceptTrack(bundle, (STHVRect){0, 0, 0, 0}, screenRect);
    STHSceneInterceptTrack(@"", card, screenRect);
    STHSceneInterceptUntrack(@"");
    assert(same(frameOf(scene.settings), screen));
  }
  puts("Scene intercept runtime: the card is pushed as the scene frame on the first pass; "
       "repeats rewrite nothing; a second ratio maps from the original rectangle; a full "
       "screen card writes nothing; closing the card restores at once and stale updates "
       "are corrected; foreign applications are untouched");
  return 0;
}
