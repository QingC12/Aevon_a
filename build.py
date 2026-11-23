"""Build stheno_2.0.33 from the frozen base.

Every binary patch that used to run at build time is already baked into
inputs/base-patched.deb and recorded in inputs/base-patched.json. This script
only compiles the two source-linked dylibs and repacks the deb, so it needs
nothing but a clang/swiftc toolchain and the debian archive tools.
"""
from pathlib import Path
import hashlib,subprocess,json,tarfile,io,copy,os,re,lzma
from concurrent.futures import ThreadPoolExecutor
from compact_sign import compact_signature
ROOT=Path(__file__).resolve().parent
os.chdir(ROOT)
OUT=ROOT/'build';OUT.mkdir(exist_ok=True)
FROZEN=json.loads((ROOT/'inputs/base-patched.json').read_text())
VERSION=FROZEN['version']
def run(*args,**kw): return subprocess.check_output([str(x) for x in args],**kw)
def arread(data):
 assert data[:8]==b'!<arch>\n';out={};p=8
 while p<len(data):
  h=data[p:p+60];assert h[58:60]==b'`\n';n=int(h[48:58]);name=h[:16].decode().strip().rstrip('/');v=data[p+60:p+60+n]
  if name.startswith('#1/'):
   z=int(name[3:]);name=v[:z].rstrip(b'\0').decode();v=v[z:]
  out[name]=v;p+=60+n+(n%2)
 return out
def arwrite(parts):
 out=bytearray(b'!<arch>\n')
 for name,b in parts:
  h=f'{name+"/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(b):<10}`\n'.encode();assert len(h)==60
  out+=h+b
  if len(b)%2:out+=b'\n'
 return out
def tarread(raw):
 with tarfile.open(fileobj=io.BytesIO(raw)) as t:
  return [(x,t.extractfile(x).read() if x.isfile() else b'') for x in t]
def tarwrite(rows):
 buf=io.BytesIO()
 with tarfile.open(fileobj=buf,mode='w:xz',format=tarfile.GNU_FORMAT) as t:
  for m,data in rows:
   m=copy.copy(m);m.size=len(data);t.addfile(m,io.BytesIO(data) if m.isfile() else None)
 return buf.getvalue()
def optimized_data_xz(blob):
 # Only repack the data archive. Decompressed TAR bytes remain identical.
 raw=lzma.decompress(blob)
 packed=lzma.compress(raw,format=lzma.FORMAT_XZ,check=lzma.CHECK_CRC64,
  filters=[{'id':lzma.FILTER_LZMA2,'preset':6,'lc':0,'lp':2,'pb':2}])
 assert lzma.decompress(packed)==raw and len(packed)<=len(blob)
 return packed
base=ROOT/'inputs/base-patched.deb'
assert hashlib.sha256(base.read_bytes()).hexdigest()==FROZEN['frozen_deb_sha256'],'base-patched.deb 与冻结记录不符'
members=arread(base.read_bytes());rows=tarread(members['data.tar.xz']);controls=tarread(members['control.tar.xz'])
mi=next(i for i,(m,b) in enumerate(rows) if m.name.endswith('/Stheno.dylib'))
cam=next(i for i,(m,b) in enumerate(rows) if m.name.endswith('/CameraFix.dylib'))
assert hashlib.sha256(rows[mi][1]).hexdigest()==FROZEN['core_sha256'],'基座 Stheno.dylib 与冻结记录不符'
core=OUT/'Stheno.dylib';core.write_bytes(rows[mi][1])
orion=OUT/'Orion';orion.write_bytes((ROOT/'inputs/Orion-private.arm64e').read_bytes())
assert hashlib.sha256(orion.read_bytes()).hexdigest()==FROZEN['orion_sha256'],'Orion 与冻结记录不符'
camera=OUT/'CameraFix.dylib';camera.write_bytes(rows[cam][1])
sdk=run('xcrun','--sdk','iphoneos','--show-sdk-path').decode().strip()
viewport_binary=OUT/'SthenoViewport.dylib'
run('xcrun','clang','-target','arm64e-apple-ios16.1','-isysroot',sdk,'-fobjc-arc','-Oz','-dynamiclib','ViewportClient.m','ViewportStartup.m','AppSceneReflow.m','ViewportBus.m','ViewportDiagnostics.m','-framework','UIKit','-framework','Foundation','-framework','CoreGraphics','-framework','QuartzCore','-install_name','@loader_path/SthenoViewport.dylib','-o',viewport_binary)
action_binary=OUT/'SthenoSystemActions.dylib'
action_sources=['SystemActions.m','SystemActionRuntime.m','SystemActionPicker.m','SystemActionIcons.m','SystemActionHooks.m','SystemCapture.m','SystemActionNative.S','ChooserCatalog.m','ChooserState.m','ChooserNative.S','CenterChooserBridge.m','CenterChooserNative.S','SystemVisibilityBridge.m','DockQueueBridge.m','DockQueueNative.S','Gesture.m','DefaultSize.m','ViewportHost.m','ViewportBus.m','ViewportDiagnostics.m','ChooserInputNative.m','core-native-stubs.S']
def compile_source(source):
 obj=OUT/(Path(source).stem+'.o')
 args=['xcrun','clang','-target','arm64e-apple-ios16.1','-isysroot',sdk,'-Oz','-c',source,'-o',obj]
 if str(source).endswith('.m'):args.insert(7,'-fobjc-arc')
 proc=subprocess.run([str(x) for x in args],capture_output=True)
 if proc.returncode:raise RuntimeError(f'{source}: {proc.stderr.decode()[-1200:]}')
 return obj
with ThreadPoolExecutor(max_workers=min(8,os.cpu_count() or 2)) as pool:
 action_objects=list(pool.map(compile_source,action_sources))
action_link=['xcrun','swiftc','-swift-version','5','-target','arm64e-apple-ios16.1','-sdk',sdk,'-Osize','-emit-library','-import-objc-header','RuntimeBridge.h','-module-name','SthenoRuntime','CenterChooser.swift','CenterSelection.swift','DockQueue.swift','ChooserSearch.swift','CenterGlyphGeometry.swift','ChooserInput.swift','ChooserFocusPolicy.swift',*action_objects,'-Xlinker','-install_name','-Xlinker','@loader_path/SthenoSystemActions.dylib','-Xlinker','-rpath','-Xlinker','/usr/lib/swift','-o',action_binary]
run(*action_link)
exported=run('xcrun','nm','-gjU',action_binary).decode().splitlines()
keep=sorted({v for v in exported if v.startswith(('_STH','_sth_','_OBJC_CLASS_$_','_OBJC_METACLASS_$_'))})
assert '_STHCenterRingPan' in keep and '_STHViewportPhysicalWill' in keep
export_list=OUT/'runtime-exports.txt';export_list.write_text('\n'.join(keep)+'\n')
run(*action_link,'-Xlinker','-exported_symbols_list','-Xlinker',export_list)
for binary in [action_binary,viewport_binary,orion]:
 run('xcrun','strip','-S','-x',binary)
signature_savings={}
for p in [core,orion,viewport_binary,action_binary,camera]:
 run('codesign','--force','--sign','-','--timestamp=none',p,stderr=subprocess.STDOUT)
 signature_savings[p.name]=compact_signature(p)
 run('codesign','--verify','--strict',p,stderr=subprocess.STDOUT)
rows[mi]=(rows[mi][0],core.read_bytes())
rows[cam]=(rows[cam][0],camera.read_bytes())
helper=copy.copy(rows[mi][0]);helper.name='./Library/MobileSubstrate/DynamicLibraries/SthenoSystemActions.dylib'
retired_keyboard_files={'SthenoKeyboard.dylib','SthenoKeyboard.plist','SthenoKb.dylib','SthenoKb.plist','KeyboardFix.dylib','KeyboardFix.plist','SthenoKeyboardInset.dylib'}
rows=[(m,b) for m,b in rows if Path(m.name).name not in retired_keyboard_files]
viewport_entry=copy.copy(helper);viewport_entry.name='./Library/MobileSubstrate/DynamicLibraries/SthenoViewport.dylib'
rows.append((viewport_entry,viewport_binary.read_bytes()))
import plistlib
viewport_filter=copy.copy(helper);viewport_filter.name='./Library/MobileSubstrate/DynamicLibraries/SthenoViewport.plist';viewport_filter.mode=0o644
rows.append((viewport_filter,plistlib.dumps({'Filter':{'Bundles':['com.apple.UIKit']}})))
action_entry=copy.copy(helper);action_entry.name='./Library/MobileSubstrate/DynamicLibraries/SthenoSystemActions.dylib'
rows.append((action_entry,action_binary.read_bytes()))
private_dir='./Library/MobileSubstrate/DynamicLibraries/.stheno'
directory=copy.copy(next(m for m,b in rows if m.isdir()));directory.name=private_dir;directory.mode=0o755;rows.append((directory,b''))
runtime_entry=copy.copy(helper);runtime_entry.name=private_dir+'/Orion';runtime_entry.mode=0o755;rows.append((runtime_entry,orion.read_bytes()))
license_entry=copy.copy(helper);license_entry.name=private_dir+'/Orion-LICENSE.txt';license_entry.mode=0o644
license_bytes=(ROOT/'inputs/Orion-LICENSE.txt').read_bytes()
assert hashlib.sha256(license_bytes).hexdigest()=='5afa9b37c934d452ecd7d3c184367657f279149add82a6d62b0ca23490b116a4'
rows.append((license_entry,license_bytes))
# Exact private image-resource allowlist; never sweep arbitrary workspace data.
icon_resources={}
icon_directory=copy.copy(directory);icon_directory.name='./Library/Application Support/Stheno/SystemActions';rows.append((icon_directory,b''))
for icon in ('screenshot','screen-recording','app-picker'):
 filename=icon+'.png';raw=(ROOT/'resources/system-actions'/filename).read_bytes()
 assert raw[:8]==b'\x89PNG\r\n\x1a\n'
 entry=copy.copy(license_entry);entry.name=icon_directory.name+'/'+filename
 rows.append((entry,raw));icon_resources[filename]=hashlib.sha256(raw).hexdigest()
for i,(m,b) in enumerate(controls):
 if Path(m.name).name=='postinst':
  controls[i]=(m,(ROOT/'installer/postinst').read_bytes());continue
 if Path(m.name).name=='control':
  fields={'Name':'stheno','Version':VERSION,'Description':'stheno','Architecture':'iphoneos-arm64e',
          'Installed-Size':str((sum(len(x) for _,x in rows)+1023)//1024)}
  lines=[];skip=False
  for line in b.decode().splitlines():
   if line.startswith((' ','\t')):
    if not skip:lines.append(line)
    continue
   field=line.partition(':')[0];skip=field=='Description'
   if field=='Depends':
    dependencies=re.split(r',\s*',line.partition(':')[2].strip())
    dependencies=[dep for dep in dependencies if not re.match(r'^dev\.theos\.orion(?:\d+)?(?:\s|$)',dep)]
    assert dependencies
    lines.append('Depends: '+', '.join(dependencies))
   else:
    lines.append(f'{field}: {fields[field]}' if field in fields else line)
  controls[i]=(m,('\n'.join(lines)+'\n').encode())
default_data_archive=tarwrite(rows)
data_tar_uncompressed=lzma.decompress(default_data_archive)
data_archive=optimized_data_xz(default_data_archive)
assert lzma.decompress(data_archive)==data_tar_uncompressed
for n,b in [('debian-binary',b'2.0\n'),('control.tar.xz',tarwrite(controls)),('data.tar.xz',data_archive)]:(OUT/n).write_bytes(b)
result=OUT/f'stheno_{VERSION}_iphoneos-arm64e.deb'
result.write_bytes(arwrite([(n,(OUT/n).read_bytes()) for n in ('debian-binary','control.tar.xz','data.tar.xz')]))
verify=tarread(arread(result.read_bytes())['data.tar.xz']);assert len(verify)==len(rows)
for (a,b),(c,d) in zip(rows,verify):assert a.name==c.name and b==d
manifest={'artifact':result.name,'sha256':hashlib.sha256(result.read_bytes()).hexdigest(),'size':result.stat().st_size,'data_tar_default_xz_bytes':len(default_data_archive),'data_tar_optimized_xz_bytes':len(data_archive),'data_tar_bytes_saved':len(default_data_archive)-len(data_archive),'data_tar_uncompressed_bytes':len(data_tar_uncompressed),'data_tar_uncompressed_sha256':hashlib.sha256(data_tar_uncompressed).hexdigest(),'patch_entries':FROZEN['patch_entries'],'device_tested':False,'merged_springboard_runtime':FROZEN['merged_springboard_runtime'],'native_bridges':FROZEN['native_bridges'],'signature_compaction':signature_savings,'runtime_export_count':len(keep),'bundled_orion':FROZEN['bundled_orion'],'keyboard_inset_adapter':False,'viewport_keyboard_rebuild':{'version':32,'legacy_files_removed':sorted(retired_keyboard_files),'original_keyboard_observer_registration_disabled':True,'single_coordinate_authority':True,'springboard_physical_source_only':True,'independent_scene_reflow':True,'main_application_post_launch_only':True,'extension_hooks_installed':False,'reflow_cached_getter':True,'private_scene_update_hook':False,'editor_transforms':False,'device_diagnostics':True},'system_actions':FROZEN['system_actions'],'center_app_chooser':{'version':3,'pins_apps':False,'native_catalog':True,'native_animated_launch':True,'native_pan_trigger':True,'release_admission':True,'ring_auto_dismiss_preserved':True,'ring_geometry_modified':False},'visibility_restores_from_observed_state':True,'initial_model_position':'native_screen_center','icon_resources':icon_resources,'update18':FROZEN['update18'],'diagnostic_logging_removed':False,'legacy_diagnostic_logging_removed':True,'base':{'frozen_deb_sha256':FROZEN['frozen_deb_sha256'],'frozen_deb_bytes':FROZEN['frozen_deb_bytes'],'core_sha256':FROZEN['core_sha256'],'core_bytes':FROZEN['core_bytes']}}
(OUT/'build-manifest.json').write_text(json.dumps(manifest,indent=2));print(json.dumps({k:manifest[k] for k in ('artifact','sha256','size','data_tar_uncompressed_bytes','data_tar_uncompressed_sha256')}))
