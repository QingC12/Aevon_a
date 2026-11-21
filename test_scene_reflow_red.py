"""Exact old source reaches UIKit before hosted/launch scoping in the model.
This demonstrates an unsafe entry path, not a captured iPhone deadlock stack.
"""
from pathlib import Path
import hashlib,resource,subprocess,tempfile
R=Path(__file__).resolve().parent
old=(R/'inputs/reflow32-negative-control.txt').read_bytes()
assert hashlib.sha256(old).hexdigest()=='17973dddfe2dbe0e5c9e179cd5b0b07b63edb14b9ff41d8fa50fc4f074a1c181'
source=old.decode()
# Skip auto-execution only so the harness can set its launch/scene-lock sentinel.
ctor='__attribute__((constructor)) static void installSceneReflow(void){STHVInstallAppSceneReflow();}'
assert source.count(ctor)==1
source=source.replace(ctor,'')
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
with tempfile.TemporaryDirectory(prefix='stheno-black-screen-red-') as d:
 p=Path(d);(p/'Reflow32.m').write_text(source);exe=p/'old32'
 subprocess.check_call(['xcrun','--sdk','macosx','clang','-fobjc-arc','-Wno-unused-parameter','-I',str(R),'-DSTH_REFLOW32_NEGATIVE',f'-DSTH_REFLOW_SOURCE="{p/"Reflow32.m"}"',str(R/'test_scene_reflow_runtime.m'),'-framework','Foundation','-framework','CoreGraphics','-framework','QuartzCore','-o',str(exe)])
 result=subprocess.run([str(exe)],capture_output=True,text=True)
 assert result.returncode!=0 and 'Assertion failed' in result.stderr and '!prohibitUIKit' in result.stderr,result.stderr
 print('Reflow32 negative control: exact SHA source touches global UIKit without any hosted layout during install; blocked-UIKit sentinel fails as expected (not a device trace)')
