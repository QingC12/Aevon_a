"""Replay the production handoff regression against exact 2.0.28 gesture code.
The baseline is reconstructed only in a temporary directory and hash-checked.
This is a host routing test, not a device input/keyboard acceptance test.
"""
from pathlib import Path
import hashlib, resource, subprocess, tempfile
R=Path(__file__).resolve().parent
BASELINE='f7e25077864f5130ee65176f24a7f75f606cd1315f509c25315af611b9118937'

def baseline_source():
    source=(R/'Gesture.m').read_text()
    start=source.index('// An input handoff can cancel SwiftUI\'s gesture without an end callback.')
    stop=source.index('// Preserve membership in the ORIGINAL hit region.',start)
    source=source[:start]+source[stop:]
    changes={
        '@property BOOL inputInterrupted;\n':'',
        '   if(native==10){interruptForInput(s);return native;}':'   if(native==10)return native;',
        ' if(original==10&&!dockedInside){interruptForInput(s);return original;}':' if(original==10&&!dockedInside)return original;',
        ' s.inputInterrupted=NO;\n':'',
        'if(!s||s.inputInterrupted)return;':'if(!s)return;',
    }
    for old,new in changes.items():
        assert old in source,('Missing reviewed baseline reconstruction',old)
        source=source.replace(old,new)
    assert hashlib.sha256(source.encode()).hexdigest()==BASELINE,'Reconstructed source drifted from exact 2.0.28'
    return source

def main():
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    with tempfile.TemporaryDirectory(prefix='stheno-handoff-red-') as tmp:
        tmp=Path(tmp);old=tmp/'Gesture28.m';old.write_text(baseline_source())
        exe=tmp/'handoff28'
        subprocess.check_call(['xcrun','--sdk','macosx','clang','-fobjc-arc','-Wall','-Wextra','-Wno-unused-parameter',
            '-DSTH_BASELINE28',f'-DSTH_GESTURE_SOURCE="{old}"',str(R/'test_floating_input_handoff.m'),
            '-framework','Foundation','-framework','CoreGraphics','-framework','QuartzCore','-o',str(exe)])
        result=subprocess.run([str(exe)],capture_output=True,text=True)
        assert result.returncode!=0,'Exact old source unexpectedly accepted the interrupted gesture'
        assert 'Assertion failed' in result.stderr and '!state(pa).dragActive' in result.stderr,result.stderr
        print('Handoff negative control: exact SHA-locked 2.0.28 production Gesture.m fails the stale-drag assertion as expected')
if __name__=='__main__':main()
