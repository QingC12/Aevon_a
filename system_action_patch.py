"""Isolated exact-image patcher: system actions only, never ring geometry."""
import struct,subprocess
from pathlib import Path
BASE=0xd9500
EXTERNAL={'_STHSystemActionCoreDlsym':0xb03bc,'_STHSystemActionOldPresent':0xd9440,'_STHSystemActionCoreOpenPlus4':0x47ec}
def instruction(source,target,link=False):
 delta=target-source
 assert delta%4==0 and -(1<<27)<=delta<(1<<27)
 return struct.pack('<I',(0x94000000 if link else 0x14000000)|((delta//4)&0x3ffffff))
def patch_system_actions(image,out):
 subprocess.check_call(['xcrun','clang','-target','arm64e-apple-ios16.1','-c','SystemActionDispatch.S','-o',str(out/'SystemActionDispatch.o')])
 obj=(out/'SystemActionDispatch.o').read_bytes();p=32;code=None;rel=None;symbols=[]
 for _ in range(struct.unpack_from('<I',obj,16)[0]):
  cmd,size=struct.unpack_from('<II',obj,p)
  if cmd==2:
   so,nn,st,ss=struct.unpack_from('<4I',obj,p+8)
   for j in range(nn):
    si,typ,sec,desc,val=struct.unpack_from('<IBBHQ',obj,so+j*16)
    symbols.append((obj[st+si:st+ss].split(b'\0')[0].decode(),sec,val))
  if cmd==0x19:
   for j in range(struct.unpack_from('<I',obj,p+64)[0]):
    q=p+72+80*j
    if obj[q:q+16].split(b'\0')[0]!=b'__text':continue
    length,off=struct.unpack_from('<QI',obj,q+40);code=bytearray(obj[off:off+length]);rel=struct.unpack_from('<II',obj,q+56)
  p+=size
 assert code is not None and rel is not None and len(code)<0xb00
 for i in range(rel[1]):
  offset,info=struct.unpack_from('<II',obj,rel[0]+8*i)
  assert info>>28==2 and (info>>27)&1
  name,section,value=symbols[info&0xffffff]
  if name in EXTERNAL:target=EXTERNAL[name]
  else:
   assert section==1,(name,section);target=BASE+value
  old=struct.unpack_from('<I',code,offset)[0];delta=target-(BASE+offset)
  assert delta%4==0 and -(1<<27)<=delta<(1<<27)
  struct.pack_into('<I',code,offset,(old&0xfc000000)|((delta//4)&0x3ffffff))
 assert image[BASE:BASE+len(code)]==bytes(len(code))
 image[BASE:BASE+len(code)]=code
 specs=[(0x47e8,bytes.fromhex('7f2303d5'),0xd9700,False),
        (0x41a9c,instruction(0x41a9c,0xd9440),0xd9500,False),
        (0xfe30,bytes.fromhex('a8835af8'),0xd9a00,True)]
 entries={}
 for at,expected,target,link in specs:
  assert image[at:at+4]==expected,(hex(at),image[at:at+4].hex())
  image[at:at+4]=instruction(at,target,link)
  entries[hex(at)]={'target':hex(target),'kind':'bl' if link else 'b','original':expected.hex()}
 return image,{'version':1,'ids':['com.nx.stheno.action.screenshot','com.nx.stheno.action.screen-recording'],'picker':'system-top-native-app-records','icon_container':'original-app','ring_geometry_modified':False,'dispatch_base':hex(BASE),'dispatch_bytes':len(code),'patches':entries}
