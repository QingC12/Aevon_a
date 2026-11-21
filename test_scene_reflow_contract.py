"""Source boundaries complement, but do not replace, on-device UIScreen tracing."""
from pathlib import Path
import subprocess,tempfile
R=Path(__file__).resolve().parent
s=(R/'AppSceneReflow.m').read_text();h=(R/'AppSceneReflowPolicy.h').read_text()
for word in ['STHVUnmodifiedScreenBounds','_boundsForInterfaceOrientation:','sceneID:updateWithSettingsDiff:transitionContext:completion:','STHVSceneIsHosted','SettingMask','Inject','1ULL<<31','STHRShouldReflow','nativeSceneUpdate(self,selector,identifier,diff,transition,completion)','if(evaluating||!NSThread.isMainThread','STHVObserveLayout','com.apple.springboard']:
 assert word in s,word
for word in ['UIKeyboard','remoteKeyboardWindow','intersectionHeight','openURL:','setFrame:','setTransform:','.frame =','.transform =','HeightFraction','cardScale','pendingSceneIdentifier']:
 assert word not in s,word
assert s.index('refreshPolicy();\n // Evaluate')<s.index('nativeSceneUpdate(self,selector')
assert 'input->settingBit31' in h and 'input->hostedLayout' in h
with tempfile.TemporaryDirectory() as d:
 out=Path(d)/'reflow';subprocess.run(['clang','-std=c11','-Wall','-Wextra','-Werror',str(R/'test_scene_reflow.c'),'-lm','-o',str(out)],check=True);subprocess.run([str(out)],check=True)
print('Scene reflow: native scene bounds, original option, hosted membership, main-screen scope and unmodified physical-screen reader; no keyboard/URL/view mutation hooks')
