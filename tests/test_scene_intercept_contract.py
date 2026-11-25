"""Boundary checks for the scene interception.

The production module is exercised against a stand-in springboard in
test_scene_intercept_runtime.m and the pure mapping in test_scene_intercept_policy.c;
this file pins the properties those runs cannot see.
"""
from pathlib import Path

R = Path(__file__).resolve().parent.parent
s = (R / 'SceneIntercept.m').read_text()
header = (R / 'SceneIntercept.h').read_text()
policy = (R / 'SceneInterceptPolicy.h').read_text()
host = (R / 'ViewportHost.m').read_text()
build = (R / 'build.py').read_text()

# Foundation only: nothing private is linked and no springboard header is pulled
# in, so the module compiles into the same runtime as everything else.
for token in ['#import <UIKit', '#import <FrontBoard', '#import <SpringBoard', '#include <UIKit',
              '#import <objc/message.h>', 'objc_msgSend', 'performSelector',
              '__attribute__((constructor))']:
    assert token not in s, ('Linked or unguarded private access', token)

# The interception point is the original's: the settings a scene is about to
# receive, and the push that carries them.
assert '@"_scene:interceptUpdateWithNewSettings:"' in s
assert '@"updateSettings:withTransitionContext:completion:"' in s
assert 'method_setImplementation' in s and 'class_getInstanceMethod' in s
# Every private send is declared on the category and guarded; the guards are the
# whole safety property for objects whose shape differs between releases.
for selector in ['settings', 'frame', 'setFrame:', 'identifier', 'clientProcess',
                 'bundleIdentifier', 'mainScene', 'scenes', 'sceneWithIdentifier:',
                 'applicationWithBundleIdentifier:']:
    assert ('@selector(%s)' % selector) in s, selector
assert s.count('respondsToSelector') >= 12

# Only the frame is written, on a mutable copy of the settings already in force,
# so no other setting can be cleared by the rewrite.
assert '[settings mutableCopy]' in s
assert s.index('[settings mutableCopy]') < s.index('[mutable setFrame:')
assert 'setFrame:' in s and 'CGRectMake(target.x, target.y, target.w, target.h)' in s
for token in ['setInterfaceOrientation', 'setLevel', 'setOcclusions', 'setDisplayConfiguration']:
    assert token not in s, ('The rewrite must stay one setting', token)

# The card is the target, a card that covers the screen writes nothing, and the
# mapping is the reviewed pure function rather than an inline formula.
assert 'STHSIMapTarget' in s and 'STHSICardIsScreen' in s
assert 'static inline bool STHSIMapTarget' in policy
assert 'card.w >= screen.w - 1.0' in policy
assert 'target.w < 80.0' in policy
# A ratio change is pushed at once and the original frame is captured once, so a
# second ratio maps from the same rectangle instead of compounding.
assert s.count('record[@"original"]') >= 2
assert 'sb-scene-push' in s and 'sb-scene-restore' in s
# No timer, no run loop observer, no queue: the registry beat drives tracking and
# the hook drives everything else.
for token in ['dispatch_', 'NSTimer', 'CFRunLoop', 'performSelector', 'sleep(']:
    assert token not in s, token
# Main thread only, and a no-op on an unreadable rectangle.
assert 'NSThread.isMainThread' in s
assert 'if (card.w < 80.0 || card.h < 80.0 || screen.w < 80.0 || screen.h < 80.0) return;' in s
assert 'void STHSceneInterceptTrack(NSString *bundle, STHVRect card, STHVRect screen);' in header
assert 'void STHSceneInterceptUntrack(NSString *bundle);' in header

# The host tracks every live card with the rectangle the application is shown and
# untracks it when the card is gone or the feature is switched off.
assert '#import "SceneIntercept.h"' in host
assert 'STHSceneInterceptTrack(bundle,card,viewportScreen());' in host
assert host.count('STHSceneInterceptUntrack(') == 2
assert 'STHScenePushViewport' not in host and 'STHScenePushRestore' not in host
assert not (R / 'ScenePush.m').exists() and not (R / 'ScenePush.h').exists()

# It is part of the shipped springboard runtime, and the module is not optional.
assert "'SceneIntercept.m'" in build or 'SceneIntercept.m' in build
assert 'ScenePush.m' not in build
print('Scene intercept boundary: original interception point, frame only, card target, '
      'one original per application, no timer, host tracks and untracks every card')
