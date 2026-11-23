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
assert 'cachedSceneBounds' in getter and 'cacheExpires' in getter
assert s.index('if(!STHVReadLayout(processBundle')<s.index('UIScreen *display=UIScreen.mainScreen')
assert 'STHVApplicationBundleAllowed' in s and 'STHVObserveApplicationLaunch' in c
assert c.index('static void activateClient')<c.index('__attribute__((constructor)) static void installClient')
assert 'STHVInstallAppSceneReflow();' in c and 'observed-post-launch' in c
for token in ['.frame =','.transform =','setFrame:','setTransform:','HeightFraction','cardScale']:
 assert token not in s,token
with tempfile.TemporaryDirectory() as d:
 out=Path(d)/'policy';subprocess.run(['clang','-std=c11','-Wall','-Wextra','-Werror',str(R/'test_scene_reflow.c'),'-lm','-o',str(out)],check=True);subprocess.run([str(out)],check=True)
print('Scene33 boundary: no reflow constructor/private scene/defaults hook; main-app post-launch only; authority checked before UIKit; bounds is original-or-expiring-cache only')
