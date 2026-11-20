"""Static contract for native picker/ring routing and opt-in system actions."""
from pathlib import Path
import ast,json,struct,hashlib,sys
R=Path(__file__).resolve().parent
sys.path.insert(0,str(R))
from system_action_patch import instruction
assert instruction(0x47e8,0xd9700)==bytes.fromhex('c6530314')
assert instruction(0xfe30,0xd9a00,True)==bytes.fromhex('f4260394')
# Byte proofs are against the original pinned arm64e input, not the arm64
# disassembly or guessed cross-architecture deltas.
raw=(R/'inputs/base.deb').read_bytes();parts={};p=8
while p<len(raw):
 h=raw[p:p+60];n=int(h[48:58]);name=h[:16].decode().strip().rstrip('/');parts[name]=raw[p+60:p+60+n];p+=60+n+n%2
import io,tarfile
with tarfile.open(fileobj=io.BytesIO(parts['data.tar.xz'])) as t:
 core=t.extractfile('./Library/MobileSubstrate/DynamicLibraries/Stheno.dylib').read()
assert hashlib.sha256(core).hexdigest()=='d5612f269f5a63347d8187fd25f75a0dca45c1608bdf38986112a5bb770fb9e7'
for offset,value in {0x47e8:'7f2303d5',0xfe30:'a8835af8',0x41a9c:'7f2303d5',0x47710:'7f2303d5',0x59870:'7f2303d5'}.items():
 assert core[offset:offset+4]==bytes.fromhex(value),(hex(offset),value)
picker=(R/'SystemActionPicker.m').read_text()
for value in ('STHSystemGrowApps(0,','STHSystemMakeSwiftString(@"截图"','STHSystemMakeSwiftString(@"录屏"','STHSystemStableFront','count+missing'):
 assert value in picker,value
for forbidden in ('LSApplicationWorkspace','LSApplicationProxy','SettingMask','setPersistentDomain','RingType'):
 assert forbidden not in picker,forbidden
icons=(R/'SystemActionIcons.m').read_text();hooks=(R/'SystemActionHooks.m').read_text()
assert 'CGSizeMake(60,60)' in icons and 'UIImageRenderingModeAlwaysOriginal' in icons
assert 'originalApplicationIcon(cls,cmd,identifier,format,scale)' in hooks
backend=(R/'SystemCapture.m').read_text()
for forbidden in ('setHasUserConsent','setSystemRecording:','setMicrophoneEnabled:','startRecordingWithHandler:', 'NSURLSession'):
 assert forbidden not in backend,forbidden
assert 'stopSystemRecording:' in backend and 'startSystemRecordingWithMicrophoneEnabled:handler:' in backend
assert '(r,start,NO,nil)' in backend and '(r,legacy,NO,nil,YES,nil)' in backend
source=(R/'SystemActions.m').read_text()
assert '.35*NSEC_PER_SEC' in source and 'STHSystemActionDismissRingNative' in source
assert 'dispatch_async(dispatch_get_main_queue(),^{execute(action);});return YES' in source
assert 'STHNativePresent' not in source and 'launchApplicationWithIdentifier' not in source
print('System action contract: exact IDs; System-top native rows; original app icons/ring; early admission dispatch; user-click-only native capture; original preferences unchanged')
