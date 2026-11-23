"""Static contract for native picker/ring routing and opt-in system actions."""
from pathlib import Path
import io,json,struct,hashlib,tarfile
R=Path(__file__).resolve().parent.parent
def branch(at,target,link=False):
 delta=target-at
 assert delta%4==0 and -(1<<27)<=delta<(1<<27)
 return struct.pack('<I',(0x94000000 if link else 0x14000000)|((delta//4)&0x3ffffff))
assert branch(0x47e8,0xd9700)==bytes.fromhex('c6530314')
assert branch(0xfe30,0xd9a00,True)==bytes.fromhex('f4260394')
# Byte proofs are against the frozen base: every hook must already be a branch,
# and the two untouched prologues must still carry their original encoding.
frozen=json.loads((R/'inputs/base-patched.json').read_text())
raw=(R/'inputs/base-patched.deb').read_bytes();parts={};p=8
while p<len(raw):
 h=raw[p:p+60];n=int(h[48:58]);name=h[:16].decode().strip().rstrip('/');parts[name]=raw[p+60:p+60+n];p+=60+n+n%2
with tarfile.open(fileobj=io.BytesIO(parts['data.tar.xz'])) as t:
 core=t.extractfile('./Library/MobileSubstrate/DynamicLibraries/Stheno.dylib').read()
assert hashlib.sha256(core).hexdigest()==frozen['core_sha256']
for at,target,link in ((0x47e8,0xd9700,False),(0x41a9c,0xd9500,False),(0xfe30,0xd9a00,True),
                       (0x81968,0xd9b00,False),(0x81c78,0xd9d00,False)):
 assert core[at:at+4]==branch(at,target,link),(hex(at),core[at:at+4].hex())
for offset in (0x47710,0x59870):
 assert core[offset:offset+4]==bytes.fromhex('7f2303d5'),hex(offset)
picker=(R/'SystemActionPicker.m').read_text()
for value in ('STHSystemGrowApps(0,','STHSystemMakeSwiftString(@"截图"','STHSystemMakeSwiftString(@"录屏"','STHSystemStableFront','count+missing'):
 assert value in picker,value
for forbidden in ('LSApplicationWorkspace','LSApplicationProxy','SettingMask','setPersistentDomain','RingType'):
 assert forbidden not in picker,forbidden
icons=(R/'SystemActionIcons.m').read_text();hooks=(R/'SystemActionHooks.m').read_text()
assert 'CGSizeMake(60,60)' in icons and 'UIImageRenderingModeAlwaysOriginal' in icons
assert 'original32(cls,cmd,identifier,format,scale)' in hooks and 'original64(cls,cmd,identifier,format,scale)' in hooks
assert "format[0]=='i'" in hooks and "format[0]=='q'" in hooks
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
