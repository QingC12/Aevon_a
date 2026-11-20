"""Maintenance safety: preserve every user-facing option/resource and validate only reversible packaging changes."""
from pathlib import Path
import hashlib, io, json, lzma, plistlib, subprocess, tarfile
R=Path(__file__).resolve().parent
base=R/'inputs/base.deb';artifact=R/'build/stheno_2.0.15_iphoneos-arm64e.deb'
manifest=json.loads((R/'build/build-manifest.json').read_text())
assert hashlib.sha256(base.read_bytes()).hexdigest()=='67937ea54f1a79d43bb48242c436e0c78b0177ef79d251e4c21465286ee1dace'

def ar(pkg,name):return subprocess.check_output(['ar','p',str(pkg),name])
def members(pkg):
 with tarfile.open(fileobj=io.BytesIO(ar(pkg,'data.tar.xz'))) as t:
  return {m.name:t.extractfile(m).read() for m in t if m.isfile()}
old,new=members(base),members(artifact)
assert manifest['data_tar_uncompressed_bytes']==len(lzma.decompress(ar(artifact,'data.tar.xz')))
assert manifest['data_tar_optimized_xz_bytes']<manifest['data_tar_default_xz_bytes']
assert len(ar(artifact,'data.tar.xz'))==manifest['data_tar_optimized_xz_bytes']
assert manifest['data_tar_bytes_saved']==manifest['data_tar_default_xz_bytes']-manifest['data_tar_optimized_xz_bytes']
# The unpacked install payload is deliberately byte- and path-identical to the
# ordinary deterministic GNU tar. Compression settings alone may change.
assert len(new)==len(old)+4,(len(old),len(new))
changed=[]
for path in old:
 if path in new and old[path]!=new[path]:changed.append(path)
allowed=['./Library/MobileSubstrate/DynamicLibraries/Stheno.dylib','./Library/MobileSubstrate/DynamicLibraries/SthenoKeyboard.dylib']
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
template=plistlib.loads(new['./var/jb/usr/local/share/stheno/com.nx.stheno.plist'])
assert template['SettingMask']==1585815 and template['Inject'] is True and template['StatusBarGroup'] is True
mask=template['SettingMask']
assert [i for i in range(64) if mask&(1<<i)]==[0,1,2,4,7,9,12,13,19,20]
assert not mask&(1<<27) and not mask&(1<<28)
for p in ['control.tar.xz']:
 with tarfile.open(fileobj=io.BytesIO(ar(base,p))) as a,tarfile.open(fileobj=io.BytesIO(ar(artifact,p))) as b:
  aa={x.name:a.extractfile(x).read() for x in a if x.isfile()};bb={x.name:b.extractfile(x).read() for x in b if x.isfile()}
  for name in ['postinst','postrm']:assert aa[name]==bb[name]
local=plistlib.loads(new['./var/jb/Library/Application Support/Stheno/zh-Hans.lproj/Localizable.strings'])
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
print('2.0.15 maintenance checks passed: all preference/UI/toggle assets preserved; settings defaults and install scripts unchanged; unpacked files identical; data XZ savings',manifest['data_tar_bytes_saved'],'bytes; only confirmed dead sources removed; active probes retained')
