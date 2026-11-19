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
delivery=(root/'KeyboardDelivery.inc').read_text()
publisher=(root/'LayoutPublisher.m').read_text()
bus=(root/'LayoutBus.m').read_text()
assert 'queueHeld' not in delivery and 'dispatch_after' not in delivery
assert 'if(status==1||status==2)' in delivery
assert 'STHReadPreview' in scene
assert '==2)return 0' not in insets
assert 'updateEditorVisibility(YES)' in coordinates
assert 'setNeedsLayout' in coordinates
assert delivery.index('normalizedInfo(note')<delivery.index('centerPost(center')
assert 'installDelivery();' in coordinates
assert 'STHSettleSample(&settling' in publisher
assert 'STHNativeAnimatePhysicalKeyboard((' not in publisher
assert 'initial-sync bundle=' in publisher
assert 't.writerActive=NO;notify_set_state(t.commit,0)' in bus # only deactivation
assert 'if(changed)notify_post' in bus # silent heartbeat, not repeated layout events
print('Production scene routing, immutable delivery, paired settle and double-buffer transport verified')
