"""Boundary checks supplement the actual production-source runtime test."""
from pathlib import Path
import subprocess,tempfile,re
R=Path(__file__).resolve().parent.parent;s=(R/'AppSceneReflow.m').read_text();c=(R/'ViewportClient.m').read_text()
for token in ['NSUserDefaults','persistentDomainForName','FBSWorkspaceScenesClient','sceneID:updateWithSettingsDiff:','_boundsForInterfaceOrientation:','__attribute__((constructor))','openURL:','UIKeyboard']:
 assert token not in s,('Global launch/scene hook returned',token)
start=s.index('static CGRect screenBounds(');end=s.index('static void publishState(',start)
getter=re.sub(r'//[^\n]*','',s[start:end])
for token in ['UIApplication','UIScreen.mainScreen','connectedScenes','STHVReadLayout','STHVLog','refreshCache','targetScene','sceneBounds(']:
 assert token not in getter,('UIKit state queried inside getter',token)
# The answer is a locked snapshot, not a pair of loose globals, and it is served
# to whatever thread asks: an application laying out on a work queue must see the
# same carded viewport the main thread sees.
assert 'cacheView()' in getter and 'os_unfair_lock' in s
assert 'NSThread.isMainThread' not in getter
assert 'cachedSceneBounds' in s and 'cacheExpires' in s
# Authority is read before any UIKit traversal, and the cache is never armed for
# an application whose host snapshot is missing or native.
assert s.index('STHVReadLayout(processBundle')<s.index('UIScreen *display=UIScreen.mainScreen')
assert 'host.hosted' in s and 'host.reflowEnabled' in s and 'STHVValid(host.card)' in s
# A card that is resizing or playing in place is neither foreground active nor
# the key scene, so neither may gate the answer or clear it.
assert 'sceneHasKeyWindow' not in s and 'UISceneActivationStateForegroundActive' not in s
assert 'UIWindowDidBecomeKeyNotification' in s and 'UIWindowDidResignKeyNotification' in s
assert '[note.name isEqual:UISceneWillDeactivateNotification]' not in s
# The carded viewport is remembered per process, so a resize that is still in
# flight cannot silently fall back to the physical screen and stay there.
assert 'hasHostedScene' in s and 'hostedScene' in s
assert 'STHVApplicationBundleAllowed' in s and 'STHVObserveApplicationLaunch' in c
assert c.index('static void activateClient')<c.index('__attribute__((constructor)) static void installClient')
assert 'STHVInstallAppSceneReflow();' in c and 'observed-post-launch' in c
for token in ['.frame =','.transform =','setFrame:','setTransform:','HeightFraction','cardScale']:
 assert token not in s,token
policy=(R/'AppSceneReflowPolicy.h').read_text()
assert 'input->sceneUsable' in policy
assert '!input->sceneForegroundActive' not in policy and '!input->sceneHasKeyWindow' not in policy
# A custom window ratio is applied by the native geometry path, which does not
# announce anything to a hosted application. The published card is therefore the
# viewport, and it is answered before the scene traversal is consulted at all, so
# a scene that lags the resize (or is ambiguous during a transition) cannot leave
# the application laid out for the previous ratio.
assert 'static inline bool STHRCardViewport' in policy
assert 'card.width < 80.0' in policy and 'STHRSceneDiffersFromPhysicalScreen(card, physical)' in policy
assert s.index('STHRCardViewport(') < s.index('cardedScene(display')
assert 'publishState(reason,YES,@"card"' in s
assert 'host.card.w' in s and 'host.card.h' in s
# The card is observed, not polled on a timer: a resize is followed by a layout
# pass in the same run loop cycle, so the answer is refreshed at the next safe
# point rather than up to one timer interval later.
assert 'CFRunLoopObserverCreateWithHandler' in s and 'dispatch_source_create' not in s
assert 'kCFRunLoopBeforeWaiting' in s and 'kCFRunLoopCommonModes' in s
# The application side only answers. A page that stopped asking cannot be
# repaired by marking views dirty, so nothing here walks a view tree, schedules a
# pass or forces a layout: the scene itself is resized from springboard, in
# SceneIntercept.m, which is the only input that rebuilds those pages.
for token in ['setNeedsLayout','layoutIfNeeded','setNeedsDisplay','nudge','walkViews',
              'subviews','noteAnswer','layoutSubviews']:
 assert token not in s,('The reflow answer must not drive layout',token)
with tempfile.TemporaryDirectory() as d:
 out=Path(d)/'policy';subprocess.run(['clang','-std=c11','-Wall','-Wextra','-Werror',str(R/'test_scene_reflow.c'),'-lm','-o',str(out)],check=True);subprocess.run([str(out)],check=True)
print('Scene33 boundary: no reflow constructor/private scene/defaults hook; main-app post-launch only; authority checked before UIKit; bounds is a locked snapshot served on any thread; carded viewport remembered across transitions')
