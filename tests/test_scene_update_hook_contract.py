"""The scene update hook is the original's mechanism, and only that.

The port dropped the private scene hooks and answered UIScreen.bounds instead,
which cannot repair a page that already laid itself out. This module puts the
hooks back. The contract is narrow on purpose: the interception point, the size
and nothing else.
"""
from pathlib import Path

R = Path(__file__).resolve().parent.parent
s = (R / 'SceneUpdateHook.m').read_text()
h = (R / 'SceneUpdateHook.h').read_text()
host = (R / 'ViewportHost.m').read_text()
build = (R / 'build.py').read_text()
manifest = (R / 'inputs/base-patched.json').read_text()

# The original's interception point, plus the scene side of the same message.
assert '_scene:interceptUpdateWithNewSettings:' in s
assert 'updateSettings:withTransitionContext:completion:' in s
for name in ['SBMainDisplaySceneManager', 'SBSceneManager', 'FBSceneManager',
             'UIMainDisplaySceneManager']:
    assert name in s, ('Manager candidate missing', name)
assert 'NSClassFromString' in s and 'class_getInstanceMethod' in s
assert 'method_setImplementation' in s

# Only the size is written. The origin is taken from the settings the system
# sent, so the frame cannot be moved by this module.
assert 'CGRectMake(frame.origin.x, frame.origin.y, width, height)' in s
for forbidden in ['frame.origin.x = ', 'card.x', 'card.y', 'STHSIMapTarget',
                  'CGAffineTransform', 'setTransform']:
    assert forbidden not in s, ('The hook must not move or scale the frame', forbidden)
assert 'fabs(frame.size.width - width) < 0.5' in s

# Foundation only: no FrontBoard or SpringBoard header, no link, no constructor,
# no timer, and every private send behind its own guard.
for header in ['#import <UIKit', '#import <FrontBoard', '#import <SpringBoard',
               '#import <objc/message.h>', 'objc_msgSend', 'performSelector',
               '__attribute__((constructor))', 'dispatch_after', 'NSTimer']:
    assert header not in s, ('The hook must stay Foundation only', header)
assert s.count('respondsToSelector:') >= 8

# A card that covers the screen is native: tracked as nothing.
assert 'fabs(card.w - screen.w) < 1.0 && fabs(card.h - screen.h) < 1.0' in s
assert 'STHSceneUpdateHookUntrack(bundle);' in s
# Closing a card puts the screen size back.
assert "record[@\"sw\"]" in s and "record[@\"sh\"]" in s
# An unusable reading never writes.
assert 'if (width < 80.0 || height < 80.0) return settings;' in s

# The host makes both calls: on the card path of the registry beat, and on every
# path where an application stops being carded.
assert 'STHSceneUpdateHookTrack(bundle,card,viewportScreen());' in host
assert 'STHSceneUpdateHookTrack(bundle,currentTarget,viewportScreen())' in host
assert host.count('STHSceneUpdateHookUntrack(bundle);') >= 2
assert '#import "SceneUpdateHook.h"' in host

# It is compiled into the springboard runtime and the manifest says so.
assert "'SceneUpdateHook.m'" in build
assert '"version": "2.0.58"' in manifest
assert "'private_scene_update_hook':True" in build
assert "'scene_update_hook'" in build

# The header names both entry points and says what is written.
assert 'void STHSceneUpdateHookTrack(NSString *bundle, STHVRect card, STHVRect screen);' in h
assert 'void STHSceneUpdateHookUntrack(NSString *bundle);' in h
assert 'Only the size is written' in h

print('Scene update hook contract: the original interception point is restored on every '
      'candidate manager class and on the scene itself; only the size of the frame is '
      'written and the origin is left as the system sent it; a full screen card and a '
      'closed card both restore the screen size; the host tracks and untracks every card '
      'and the manifest states the hook')
