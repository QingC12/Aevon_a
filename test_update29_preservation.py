"""Enforce the user's accepted-keyboard freeze and the narrow host-only edits."""
from pathlib import Path
import hashlib,json
from test_floating_handoff_red import baseline_source
R=Path(__file__).resolve().parent

def digest(value):return hashlib.sha256(value).hexdigest()
def verify():
    baseline=json.loads((R/'inputs/accepted-keyboard-and-floating-2.0.28.json').read_text())
    for name,expected in baseline['unchanged_production_files'].items():
        assert digest((R/name).read_bytes())==expected,('Accepted production path changed',name)
    baseline_source() # Exact old gesture source must still be reconstructible.
    source=(R/'Keyboard.m').read_text()
    source=source.replace('extern void STHCardRunExpansion(void (^block)(void));\n','').replace('extern void STHGestureInputFocusChanged(void *);\n','')
    source=source.replace(' if(!same){STHGestureInputFocusChanged(model);STHPrepareLayoutFocus(model);}',' if(!same)STHPrepareLayoutFocus(model);')
    scoped='''#if !defined(STH_KEYBOARD_TEST) || defined(STH_KEYBOARD_INPUT_TEST)
  double scale=target[0],x=target[1],y=target[2];
  STHCardRunExpansion(^{const double geometry[3]={scale,x,y};STHNativeSetKeyboardGeometry((__bridge void *)focus,geometry);});
#else
  STHNativeSetKeyboardGeometry((__bridge void *)focus,target);
#endif'''
    assert scoped in source
    source=source.replace(scoped,'  STHNativeSetKeyboardGeometry((__bridge void *)focus,target);')
    assert digest(source.encode())==baseline['keyboard_baseline_sha256'],'Unexpected change outside host card animation/focus interruption'
    build=(R/'build.py').read_text().replace("VERSION='2.0.29'","VERSION='2.0.28'").replace("'DockQueueNative.S','CardExpansion.S','Gesture.m'","'DockQueueNative.S','Gesture.m'")
    assert digest(build.encode())==baseline['build_baseline_sha256'],'Unexpected build or app-side compiler change'
    print('Accepted keyboard preservation: 80 production files match remote 2.0.28; app insets/editors/delivery/transport/native springs and ring unchanged; host-only diff verified')
if __name__=='__main__':verify()
