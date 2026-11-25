"""The card is published to the application as its own scene rectangle.

Answering a getter and marking views dirty cannot repair a page that sampled the
width while the card was moving: the page stopped asking, so only a real change of
the scene makes UIKit run the size transition that rebuilds it. The publication
therefore lives on the springboard side, resolves every private object by name,
and writes nothing but the frame.
"""
from pathlib import Path
R = Path(__file__).resolve().parent.parent
s = (R / 'ScenePush.m').read_text()
h = (R / 'ScenePush.h').read_text()
host = (R / 'ViewportHost.m').read_text()
reflow = (R / 'AppSceneReflow.m').read_text()
build = (R / 'build.py').read_text()

# Compiled into the springboard runtime, called only from the host.
assert "'ScenePush.m'" in build
assert '#import "ScenePush.h"' in host
assert 'void STHScenePushViewport(NSString *bundle, STHVRect card, STHVRect screen);' in h
assert 'void STHScenePushRestore(NSString *bundle);' in h

# The application side must never write a scene frame: it only answers reads.
for token in ['setFrame:', 'updateSettings:withTransitionContext:', 'SBApplication',
              'FBScene', 'NSClassFromString']:
    assert token not in reflow, token
    assert token not in host, token

# Only the frame is written, from a mutable copy of the settings already in force,
# so nothing else the scene was carrying can be cleared by this update.
assert 'mutableCopy' in s and '@selector(setFrame:)' in s
assert '@selector(updateSettings:withTransitionContext:completion:)' in s

# Every private object is resolved by name and every message is guarded, because
# the shapes differ between releases and a wrong guess has to be a no-op.
assert 'NSClassFromString' in s
assert '@"SBApplicationController"' in s and '@"FBSceneManager"' in s
assert 'respondsToSelector' in s and s.count('respondsToSelector') >= 6
assert '@try' in s and '@catch' in s
# A handle that wraps the scene is unwrapped before it is used.
assert 'static id sthUnwrapScene(id candidate)' in s and '@selector(scene)' in s

# Main thread only, no constructor, no timer, no block retained by a queue.
assert s.count('NSThread.isMainThread') >= 2
for token in ['dispatch_', '__attribute__((constructor))', 'NSTimer', 'performSelector:withObject:afterDelay:']:
    assert token not in s, token

# The original frame is read once; every ratio derives from it, so a repeated
# beat with an unchanged card writes nothing.
assert 'sthStoreRect(entry, @"original", original)' in s
assert 'sthLoadRect(entry, @"original", &original)' in s
# Foundation only: the CGRect boxing category belongs to UIKit and is not linked.
assert 'NSValue valueWithCGRect' not in s and 'CGRectValue' not in s
assert 'static BOOL sthSameRect(CGRect a, CGRect b)' in s
assert 'if (sthSameRect(current, target))' in s
# The current scene frame decides, not a remembered target: a dropped or reverted
# update has to be written again.
assert 'CGRect current = [settings frame];' in s

# A card that covers the screen is not a card, and the frame it replaced is put
# back; a store that can never be found must not spin.
assert 'card.w >= screen.w - 1.0 && card.h >= screen.h - 1.0' in s
assert 'STHScenePushRestore(bundle);' in s
assert 'entry[@"retryAt"] = @(now + 2.0)' in s

# Published from the card path of the registry beat, and put back when the card
# closes or the feature is switched off.
assert 'STHScenePushViewport(bundle,card,viewportScreen())' in host
assert host.count('STHScenePushRestore(bundle)') >= 2
print('Scene publication: springboard only, frame only, guarded resolution, idempotent per card, restored on close')
