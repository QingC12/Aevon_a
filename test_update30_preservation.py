"""Accepted 2.0.28 keyboard sources, original transitions and 2.0.29 touch fix."""
from pathlib import Path
import hashlib,json,sys
from test_native_transition_red import source29
from test_published_bridge_abi import Image,calls
R=Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
def verify(folder=None):
    accepted=json.loads((R/'inputs/accepted-keyboard-and-floating-2.0.28.json').read_text())
    for name,digest in accepted['unchanged_production_files'].items():
        assert sha((R/name).read_bytes())==digest,('Accepted production file changed',name)
    assert sha((R/'Gesture.m').read_bytes())=='9514eee8a19809a1be58279692b6216022d0ead5d8c6380763e3bae24d95ffb1','2.0.29 touch cleanup changed'
    source29() # Only reviewed changes to the exact old host source are accepted.
    build=(R/'build.py').read_text().replace("VERSION='2.0.30'","VERSION='2.0.28'")
    assert sha(build.encode())==accepted['build_baseline_sha256'],'Build differs beyond original object set/version'
    assert not (R/'CardExpansion.S').exists(),'Dead independent spring source must be removed'
    assert 'STHCardRunExpansion' not in (R/'Keyboard.m').read_text()
    if folder:
        from embed_orion import exports
        image=Image(Path(folder)/'SthenoSystemActions.dylib')
        assert '_STHCardRunExpansion' not in exports(image.data),'Old nested spring still linked'
        assert '_STHGestureInputFocusChanged' in exports(image.data),'Touch interruption fix lost'
        words=image.words('_STHCenterRunAnimation')
        targets=[target for target,_ in calls(words,image.symbols['_STHCenterRunAnimation'])]
        assert targets==[0x51454,0x51454,0xafb5c,0xafb4c,0xaf19c,0xb0a0c],list(map(hex,targets))
        assert 0x1e616801 not in words,'No damping floor/custom spring is allowed'
    print('2.0.30 preservation: accepted 80 production files frozen; 2.0.29 touch fix retained; 2.0.28 target math and original native spring/object set restored; no nested card animation')
if __name__=='__main__':verify(Path(sys.argv[1]) if len(sys.argv)>1 else None)
