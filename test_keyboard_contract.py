"""Structural checks on production routing; math tests cover the same data cases.
These do not claim to reproduce private third-party app UI on an iPhone.
"""
from pathlib import Path
root=Path(__file__).resolve().parent
coordinates=(root/'KeyboardCoordinates.m').read_text()
insets=(root/'KeyboardInset.m').read_text()
scene=coordinates.split('BOOL STHResolveKeyboardScene(',1)[1].split('static void decision',1)[0]
assert 'STHReadLayout(NSBundle.mainBundle.bundleIdentifier,bounds,' in scene
assert 'target.bounds' not in scene # must not derive scene inset from popup size
assert 'CGRect result=canonical(bounds,raw)' in scene
assert '*inset=result.size.height' in scene
assert 'STHResolveKeyboardScene(scene,keyboard,CGRectNull' in insets
assert 'com.apple.springboard' in insets and 'com.apple.UIKit.remote-keyboard' in insets
refresh=coordinates.split('static void refreshHostedLayout',1)[1].split('void STHInstallKeyboardNotifications',1)[0]
assert refresh.index('STHSessionCommit')<refresh.index('postNotification:')
assert 'objc_setAssociatedObject(note,&normalizedKey,@YES' in refresh
assert 'UIKeyboardDidChangeFrameNotification' in refresh
assert 'latestScreenFrame' not in coordinates
assert 'STHSessionPhysical(&session' in coordinates
print('Production scene-only routing, synthetic isolation and keyboard process exclusion verified')
