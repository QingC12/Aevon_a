from pathlib import Path
import hashlib,struct,subprocess,json,sys,tarfile,io,shutil,copy,os
ROOT=Path(__file__).resolve().parent
os.chdir(ROOT)
OUT=ROOT/'build';OUT.mkdir(exist_ok=True)
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
def sections(b):
 n=struct.unpack_from('<I',b,16)[0];p=32;secs={};cmds=[]
 for _ in range(n):
  cmd,size=struct.unpack_from('<II',b,p);cmds.append((cmd,p,size))
  if cmd==0x19:
   count=struct.unpack_from('<I',b,p+64)[0]
   for j in range(count):
    q=p+72+80*j;name=b[q:q+16].split(b'\0')[0].decode();a,s,o=struct.unpack_from('<QQI',b,q+32);secs[name]=(a,s,o)
  p+=size
 return secs,cmds
def branch(a,b):
 d=b-a;assert d%4==0 and -(1<<27)<=d<(1<<27)
 return struct.pack('<I',0x14000000|((d//4)&0x3ffffff))
def tarread(raw):
 with tarfile.open(fileobj=io.BytesIO(raw)) as t:
  return [(x,t.extractfile(x).read() if x.isfile() else b'') for x in t]
def tarwrite(rows):
 buf=io.BytesIO()
 with tarfile.open(fileobj=buf,mode='w:xz',format=tarfile.GNU_FORMAT) as t:
  for m,data in rows:
   m=copy.copy(m);m.size=len(data);t.addfile(m,io.BytesIO(data) if m.isfile() else None)
 return buf.getvalue()
base=ROOT/'inputs/base.deb'
assert hashlib.sha256(base.read_bytes()).hexdigest()=='67937ea54f1a79d43bb48242c436e0c78b0177ef79d251e4c21465286ee1dace'
members=arread(base.read_bytes());rows=tarread(members['data.tar.xz']);controls=tarread(members['control.tar.xz'])
mi=next(i for i,(m,b) in enumerate(rows) if m.name.endswith('/Stheno.dylib'));img=bytearray(rows[mi][1])
assert hashlib.sha256(img).hexdigest()=='d5612f269f5a63347d8187fd25f75a0dca45c1608bdf38986112a5bb770fb9e7'
secs,cmds=sections(img)
assert img[0xd9000:0xdc000]==bytes(0x3000)
# Assemble and link a position-fixed, self-contained dispatcher into existing executable padding.
run('xcrun','clang','-target','arm64e-apple-ios16.1','-c','dispatch.S','-o',OUT/'dispatch.o')
temp=(OUT/'dispatch.o').read_bytes();sec,cmds_o=sections(temp);_,size,off=sec['__text'];code=bytearray(temp[off:off+size]);address=0xd9000
symbols=[];rel=None
for cmd,p,sz in cmds_o:
 if cmd==2:
  so,nn,st,ss=struct.unpack_from('<4I',temp,p+8)
  for j in range(nn):
   si,typ,se,desc,val=struct.unpack_from('<IBBHQ',temp,so+j*16);name=temp[st+si:st+ss].split(b'\0')[0].decode();symbols.append((name,typ,se,val))
 if cmd==0x19:
  ns=struct.unpack_from('<I',temp,p+64)[0]
  for j in range(ns):
   q=p+72+j*80
   if temp[q:q+16].split(b'\0')[0]==b'__text':rel=struct.unpack_from('<II',temp,q+56)
absolute={'_dlsym':0xb03bc,'_original_setup_plus4':0x4994c,'_original_update_plus4':0x4ad48,'_original_end_plus4':0x4c368,'_original_long_plus4':0x3e420,'_original_tap_plus4':0x3e77c}
assert rel is not None
for j in range(rel[1]):
 r,info=struct.unpack_from('<II',temp,rel[0]+8*j);ix=info&0xffffff;typ=info>>28;external=(info>>27)&1
 assert typ==2 and external==1,(hex(r),hex(info))
 name,symtype,sect,value=symbols[ix];target=absolute.get(name)
 if target is None:
  assert sect==1,(name,sect);target=address+value
 inst=struct.unpack_from('<I',code,r)[0];delta=target-(address+r)
 assert delta%4==0 and -(1<<27)<=delta<(1<<27)
 struct.pack_into('<I',code,r,(inst&0xfc000000)|((delta//4)&0x3ffffff))
assert size<0x1000
img[address:address+size]=code
# Entry hooks are all PAC prologues, except the known classifier tail branch.
changes={0x3dff0:(bytes.fromhex('64660214'),0xd9100),0x49948:(bytes.fromhex('7f2303d5'),0xd9140),0x4ad44:(bytes.fromhex('7f2303d5'),0xd9180),0x4c364:(bytes.fromhex('7f2303d5'),0xd91c0),0x3e41c:(bytes.fromhex('7f2303d5'),0xd9200),0x3e778:(bytes.fromhex('7f2303d5'),0xd9240)}
for a,(old,target) in changes.items():
 assert img[a:a+4]==old,(hex(a),img[a:a+4].hex())
 img[a:a+4]=branch(a,target)
# Quarter-second hold and a single-click recognizer; custom dispatch controls applicable zones.
assert img[0x9b54:0x9b58]==bytes.fromhex('00106c1e')
(OUT/'constants.S').write_text('.text\nfmov d0, #0.25\nmov x0,#1\n')
run('xcrun','clang','-target','arm64e-apple-ios16.1','-c',OUT/'constants.S','-o',OUT/'constants.o')
ob=(OUT/'constants.o').read_bytes();sc,_=sections(ob);_,sz,off=sc['__text'];code=ob[off:off+sz]
img[0x9b54:0x9b58]=code[:4]
assert img[0x9c4c:0x9c50]==bytes.fromhex('0015889a');img[0x9c4c:0x9c50]=code[4:8]
# Always visit the end bridge so it can clear active-touch state even after a hold.
assert struct.unpack_from('<I',img,0xaa18)[0]&0x7e000000==0x36000000
img[0xaa18:0xaa1c]=bytes.fromhex('1f2003d5')
# Dependency loads before any of the patched entry points.
name=b'@loader_path/SthenoGesture.dylib\0';sz=(24+len(name)+7)&~7
lc=struct.pack('<6I',0xc,sz,24,2,0x10000,0x10000)+name;lc+=bytes(sz-len(lc))
n,nbytes=struct.unpack_from('<II',img,16);at=32+nbytes
assert at+sz<0x4000 and img[at:at+sz]==bytes(sz)
img[at:at+sz]=lc;struct.pack_into('<II',img,16,n+1,nbytes+sz)
core=OUT/'Stheno.dylib';core.write_bytes(img)
# Compile recovered dispatch source, not the proprietary original project.
run('xcrun','clang','-target','arm64e-apple-ios16.1','-isysroot',run('xcrun','--sdk','iphoneos','--show-sdk-path').decode().strip(),'-fobjc-arc','-O2','-dynamiclib','Gesture.m','native.S','-framework','UIKit','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics','-install_name','@loader_path/SthenoGesture.dylib','-o',OUT/'SthenoGesture.dylib')
for p in [core,OUT/'SthenoGesture.dylib']:
 run('codesign','--force','--sign','-','--timestamp=none',p,stderr=subprocess.STDOUT)
 run('codesign','--verify','--strict',p,stderr=subprocess.STDOUT)
 rows[mi]=(rows[mi][0],core.read_bytes())
helper=copy.copy(rows[mi][0]);helper.name='./Library/MobileSubstrate/DynamicLibraries/SthenoGesture.dylib';rows.append((helper,(OUT/'SthenoGesture.dylib').read_bytes()))
for i,(m,b) in enumerate(controls):
 if Path(m.name).name=='control':
  fields={'Name':'stheno','Version':'2.0.1+fix1','Description':'stheno','Architecture':'iphoneos-arm64e',
          'Installed-Size':str((sum(len(x) for _,x in rows)+1023)//1024)}
  lines=[];skip=False
  for line in b.decode().splitlines():
   if line.startswith((' ','\t')):
    if not skip:lines.append(line)
    continue
   field=line.partition(':')[0];skip=field=='Description'
   lines.append(f'{field}: {fields[field]}' if field in fields else line)
  controls[i]=(m,('\n'.join(lines)+'\n').encode())
for n,b in [('debian-binary',b'2.0\n'),('control.tar.xz',tarwrite(controls)),('data.tar.xz',tarwrite(rows))]:(OUT/n).write_bytes(b)
result=OUT/'stheno_2.0.1+fix1_iphoneos-arm64e.deb'
result.write_bytes(arwrite([(n,(OUT/n).read_bytes()) for n in ('debian-binary','control.tar.xz','data.tar.xz')]))
verify=tarread(arread(result.read_bytes())['data.tar.xz']);assert len(verify)==len(rows)
for (a,b),(c,d) in zip(rows,verify):assert a.name==c.name and b==d
manifest={'artifact':result.name,'sha256':hashlib.sha256(result.read_bytes()).hexdigest(),'size':result.stat().st_size,'patch_entries':{hex(a):hex(t) for a,(_,t) in changes.items()},'device_tested':False}
(OUT/'build-manifest.json').write_text(json.dumps(manifest,indent=2));print(json.dumps(manifest))
