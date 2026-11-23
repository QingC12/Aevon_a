from pathlib import Path
import hashlib,io,json,struct,sys,tarfile
from macho import exports
R=Path(__file__).resolve().parent
folder=Path(sys.argv[1]) if len(sys.argv)>1 else R/'build'
m=json.loads((folder/'build-manifest.json').read_text())
def entries(pkg):
 raw=Path(pkg).read_bytes();p=8;ar={}
 while p<len(raw):
  h=raw[p:p+60];size=int(h[48:58]);name=h[:16].decode().strip().rstrip('/');ar[name]=raw[p+60:p+60+size];p+=60+size+(size&1)
 out={}
 for kind in ['data','control']:
  with tarfile.open(fileobj=io.BytesIO(ar[kind+'.tar.xz'])) as t:out[kind]={x.name:t.extractfile(x).read() for x in t if x.isfile()}
 return out
old=entries(R/'inputs/base.deb');new=entries(folder/m['artifact'])
core_path='./Library/MobileSubstrate/DynamicLibraries/Stheno.dylib'
core=new['data'][core_path];base=old['data'][core_path]
assert m['merged_springboard_runtime'] and len(new['data'])==29
assert not any(k.endswith('/SthenoGesture.dylib') for k in new['data'])
# All original code and constants remain exact outside documented patch words/padding.
allowed={int(x,16) for x in m['patch_entries']}
allowed.update(int(x,16) for x in m['system_actions']['patches'])
for group in ['center','dock']:allowed.update(int(x,16) for x in m['update18'][group]['patches'])
allowed.update([0x9b54,0x9c4c,0xaa18,0x3c11c])
allowed_bytes={x+i for x in allowed for i in range(4)}
drift=[i for i in range(0x4000,0xd9000) if base[i]!=core[i] and i not in allowed_bytes]
assert not drift,('unreviewed original code/constants drift',drift[:20])
meta=m['native_bridges'];assert meta['base']==0xda600 and meta['end']<=0xdc000
assert hashlib.sha256(core[meta['base']:meta['end']]).hexdigest()==meta['code_sha256']
assert len(meta['exports'])==21
names=exports(new['data']['./Library/MobileSubstrate/DynamicLibraries/SthenoSystemActions.dylib'])
required=set(meta['exports'])|{'_STHClassify','_STHSetup','_STHUpdate','_STHEnd','_STHTap','_STHLong','_STHFirstPresentation','_STHViewportPhysicalWill','_STHViewportSetLocalInput','_STHViewportKeyboardExcludes','_STHCreateChooserInputWindow','_STHAcquireChooserKeyboardFocus','_STHReleaseChooserKeyboardFocus','_STHViewportModelMinimized','_STHCenterRingPan','_STHDockReflow','_STHSystemActionPresent'}
assert required<=names,sorted(required-names)
assert exports((R/'inputs/Orion-private.arm64e').read_bytes())==exports(new['data']['./Library/MobileSubstrate/DynamicLibraries/.stheno/Orion'])
retired=set(m['viewport_keyboard_rebuild']['legacy_files_removed'])
assert not any(Path(k).name in retired for k in new['data'])
for path,value in old['data'].items():
 if Path(path).name in retired:continue
 if not value.startswith(b'\xcf\xfa\xed\xfe'):assert value==new['data'][path],path
control=next(v.decode() for k,v in new['control'].items() if Path(k).name=='control')
installed=int(next(s.split(':',1)[1] for s in control.splitlines() if s.startswith('Installed-Size:')))
assert installed==(sum(len(x) for x in new['data'].values())+1023)//1024
print('Runtime package: 21 core-resident bridges,',len(required),'required callbacks, exact original code outside documented patches, 29 payload files, all inherited resources exact')
