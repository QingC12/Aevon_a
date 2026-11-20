import struct,subprocess
from pathlib import Path
from center_action_patch import patch_center_action
from system_action_patch import instruction

def patch_update18(image,out):
 image,center=patch_center_action(image,out)
 base=0xda400
 external={'_STHDockCoreDlsym':0xb03bc,'_STHDockMinimizePlus4':0x447d8,'_STHDockRestorePlus4':0x449e0,'_STHDockGeometryPlus4':0x9d7f8}
 subprocess.check_call(['xcrun','clang','-target','arm64e-apple-ios16.1','-c','DockDispatch.S','-o',str(out/'DockDispatch.o')])
 raw=(out/'DockDispatch.o').read_bytes();p=32;symbols=[];code=None;rel=None
 for _ in range(struct.unpack_from('<I',raw,16)[0]):
  cmd,size=struct.unpack_from('<II',raw,p)
  if cmd==2:
   so,nn,st,ss=struct.unpack_from('<IIII',raw,p+8)
   for j in range(nn):
    si,typ,sec,desc,value=struct.unpack_from('<IBBHQ',raw,so+16*j);symbols.append((raw[st+si:st+ss].split(b'\0')[0].decode(),sec,value))
  if cmd==0x19:
   for j in range(struct.unpack_from('<I',raw,p+64)[0]):
    q=p+72+80*j
    if raw[q:q+16].split(b'\0')[0]==b'__text':
     length,offset=struct.unpack_from('<QI',raw,q+40);code=bytearray(raw[offset:offset+length]);rel=struct.unpack_from('<II',raw,q+56)
  p+=size
 assert code is not None and len(code)<0x200 and rel
 for i in range(rel[1]):
  offset,flags=struct.unpack_from('<II',raw,rel[0]+8*i);assert flags>>28==2 and (flags>>27)&1
  name,section,value=symbols[flags&0xffffff];assert name in external or section==1
  target=external.get(name,base+value);old=struct.unpack_from('<I',code,offset)[0]
  delta=target-base-offset;assert delta%4==0
  struct.pack_into('<I',code,offset,(old&0xfc000000)|((delta//4)&0x3ffffff))
 assert image[base:base+len(code)]==bytes(len(code));image[base:base+len(code)]=code
 sites={0x447d4:base,0x449dc:base+0x80,0x9d7f4:base+0x100}
 for at,target in sites.items():
  assert image[at:at+4]==bytes.fromhex('7f2303d5');image[at:at+4]=instruction(at,target)
 assert image[0x3c11c:0x3c120]==bytes.fromhex('7f2303d5')
 image[0x3c11c:0x3c120]=bytes.fromhex('c0035fd6')
 return image,{'quiet_core_logger':{'address':'0x3c11c','kind':'ret'},'center':center,'dock':{'dispatch_base':hex(base),'dispatch_bytes':len(code),'patches':{hex(a):{'kind':'b','target':hex(t),'original':'7f2303d5'} for a,t in sites.items()}},'original_animation_transactions':True}
