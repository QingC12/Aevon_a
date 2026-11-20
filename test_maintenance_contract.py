"""Maintenance safety: preserve every user-facing option/resource and validate only reversible packaging changes."""
from pathlib import Path
import hashlib, io, json, lzma, plistlib, tarfile
R=Path(__file__).resolve().parent
base=R/'inputs/base.deb'
manifest=json.loads((R/'build/build-manifest.json').read_text())
artifact=R/'build'/manifest['artifact']
assert hashlib.sha256(base.read_bytes()).hexdigest()=='67937ea54f1a79d43bb48242c436e0c78b0177ef79d251e4c21465286ee1dace'

def ar_members(pkg):
 raw=Path(pkg).read_bytes();assert raw[:8]==b'!<arch>\n';out={};pos=8
 while pos<len(raw):
  header=raw[pos:pos+60];assert header[58:60]==b'`\n';size=int(header[48:58]);name=header[:16].decode().strip().rstrip('/')
  payload=raw[pos+60:pos+60+size]
  if name.startswith('#1/'):
   n=int(name[3:]);name=payload[:n].rstrip(b'\0').decode();payload=payload[n:]
  out[name]=payload;pos+=60+size+(size%2)
 return out
def ar(pkg,name):return ar_members(pkg)[name]
def members(pkg):
 with tarfile.open(fileobj=io.BytesIO(ar(pkg,'data.tar.xz'))) as t:
  return {m.name:t.extractfile(m).read() for m in t if m.isfile()}
old,new=members(base),members(artifact)
artifact_bytes=artifact.read_bytes()
assert manifest['artifact']==artifact.name and manifest['size']==len(artifact_bytes)
assert manifest['sha256']==hashlib.sha256(artifact_bytes).hexdigest()
data_archive=ar(artifact,'data.tar.xz');data_raw=lzma.decompress(data_archive)
assert manifest['data_tar_uncompressed_bytes']==len(data_raw)
assert manifest['data_tar_uncompressed_sha256']==hashlib.sha256(data_raw).hexdigest()
assert manifest['data_tar_optimized_xz_bytes']<manifest['data_tar_default_xz_bytes']
assert len(data_archive)==manifest['data_tar_optimized_xz_bytes']
assert manifest['data_tar_bytes_saved']==manifest['data_tar_default_xz_bytes']-len(data_archive)
# Independently recompress with ordinary XZ and verify the same unpacked TAR.
ordinary=lzma.compress(data_raw)
assert len(ordinary)==manifest['data_tar_default_xz_bytes']
assert lzma.decompress(ordinary)==data_raw
# Exact file allowlist: no inherited file may disappear and no accidental
# source, cache, debug output or extra payload may enter the package.
added={
 './Library/MobileSubstrate/DynamicLibraries/SthenoGesture.dylib',
 './Library/MobileSubstrate/DynamicLibraries/SthenoKeyboardInset.dylib',
 './Library/MobileSubstrate/DynamicLibraries/.stheno/Orion',
 './Library/MobileSubstrate/DynamicLibraries/.stheno/Orion-LICENSE.txt',
}
if manifest.get('system_actions'):
 added.add('./Library/MobileSubstrate/DynamicLibraries/SthenoSystemActions.dylib')
if manifest.get('icon_resources'):
 assert len(manifest['icon_resources'])==9
 for filename,digest in manifest['icon_resources'].items():
  assert '/' not in filename and filename.endswith('.png')
  path='./Library/Application Support/Stheno/SystemActions/'+filename
  added.add(path);assert hashlib.sha256(new[path]).hexdigest()==digest
assert set(new)==set(old)|added,(set(old)-set(new),set(new)-set(old)-added)
changed={path for path in old if old[path]!=new[path]}
allowed={'./Library/MobileSubstrate/DynamicLibraries/Stheno.dylib','./Library/MobileSubstrate/DynamicLibraries/SthenoKeyboard.dylib'}
assert changed==allowed,changed
for path in ['./usr/local/share/stheno/com.nx.stheno.plist',
 './Library/PreferenceBundles/SthenoPreference.bundle/Info.plist',
 './Library/PreferenceBundles/SthenoPreference.bundle/Root.plist',
 './Library/PreferenceBundles/SthenoPreference.bundle/SthenoPreference',
 './Library/PreferenceBundles/SthenoPreference.bundle/en.lproj/Localizable.strings',
 './Library/PreferenceBundles/SthenoPreference.bundle/zh-Hans.lproj/Localizable.strings',
 './Library/PreferenceLoader/Preferences/SthenoPreference.plist',
 './Library/Application Support/Stheno/en.lproj/Localizable.strings',
 './Library/Application Support/Stheno/zh-Hans.lproj/Localizable.strings']:
 assert old[path]==new[path],f'user setting or preference UI modified: {path}'
template=plistlib.loads(new['./usr/local/share/stheno/com.nx.stheno.plist'])
assert template['SettingMask']==1585815 and template['Inject'] is True and template['StatusBarGroup'] is True
mask=template['SettingMask']
assert [i for i in range(64) if mask&(1<<i)]==[0,1,2,4,7,9,12,13,19,20]
assert not mask&(1<<27) and not mask&(1<<28)
for p in ['control.tar.xz']:
 with tarfile.open(fileobj=io.BytesIO(ar(base,p))) as a,tarfile.open(fileobj=io.BytesIO(ar(artifact,p))) as b:
  aa={Path(x.name).name:a.extractfile(x).read() for x in a if x.isfile()};bb={Path(x.name).name:b.extractfile(x).read() for x in b if x.isfile()}
  for name in ['postinst','postrm']:assert aa[name]==bb[name]
local=plistlib.loads(new['./Library/Application Support/Stheno/zh-Hans.lproj/Localizable.strings'])
for key in ['BlockInterceptor','SSInterceptor','SSInterceptorSilence','SSListen','SSNoUniversalLinks','SSNoSafariViewService','ForegroundNotify','FrontmostNotify','HookUIKit']:
 assert key in local,key

# Explicit production compiler closure. Tests, audit notes, probes remain source
# tools but none enter the DEB as accidental data files.
build=(R/'build.py').read_text()
for src in ['Gesture.m','Keyboard.m','DefaultSize.m','LayoutPublisher.m','NotificationPolicy.m','LayoutBus.m','LayoutProbe.m','EditorGuard.m','EditorPolicy.m','EditorRefinedGuard.m','EditorCompositeGuard.m','KeyboardMeasurement.m','KeyboardRefinedMeasurement.m','KeyboardCompositeMeasurement.m']:
 assert f"'{src}'" in build,src
for removed in ['GestureRules.h','test_gesture_rules.c','KeyboardInsetMath.h','test_keyboard_inset.c','EditorVisibility.m']:
 assert not (R/removed).exists(),removed
for live in ['LayoutProbe.m','LayoutProbe.h','NotificationPolicy.m','EditorVisibilityMath.h','KeyboardCoordinates.h']:
 assert (R/live).exists(),live
assert '.gitignore' in [p.name for p in R.iterdir()]
print('Maintenance checks passed: all original preference/UI/toggle assets preserved; settings defaults and install scripts unchanged; compression round-trip identical; data XZ savings',manifest['data_tar_bytes_saved'],'bytes; only allowlisted runtime modules added; active probes retained')
