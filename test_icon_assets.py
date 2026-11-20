from pathlib import Path
import struct,zlib,hashlib
R=Path(__file__).resolve().parent/'resources/system-actions'
def decode(raw):
 assert raw[:8]==b'\x89PNG\r\n\x1a\n';p=8;data=b''
 while p<len(raw):
  n=struct.unpack_from('>I',raw,p)[0];kind=raw[p+4:p+8];value=raw[p+8:p+8+n]
  assert zlib.crc32(kind+value)&0xffffffff==struct.unpack_from('>I',raw,p+8+n)[0]
  if kind==b'IHDR':w,h,depth,color,*_=struct.unpack('>IIBBBBB',value);assert depth==8 and color==6
  if kind==b'IDAT':data+=value
  p+=n+12
 raw=zlib.decompress(data);rows=[];stride=w*4;prior=bytearray(stride);p=0
 for _ in range(h):
  mode=raw[p];p+=1;row=bytearray(raw[p:p+stride]);p+=stride
  for i in range(stride):
   a=row[i-4] if i>=4 else 0;b=prior[i];c=prior[i-4] if i>=4 else 0
   if mode==1:v=a
   elif mode==2:v=b
   elif mode==3:v=(a+b)//2
   elif mode==4:
    q=a+b-c;da,db,dc=abs(q-a),abs(q-b),abs(q-c);v=a if da<=db and da<=dc else (b if db<=dc else c)
   else:assert mode==0;v=0
   row[i]=(row[i]+v)&255
  rows.append(row);prior=row
 return w,h,rows
hashes=[]
for name in ('screenshot','screen-recording','app-picker'):
 for scale in (1,):
  suffix='' if scale==1 else f'@{scale}x';p=R/(name+suffix+'.png');raw=p.read_bytes();w,h,rows=decode(raw);assert w==h==60*scale
  def pixel(x,y):return tuple(rows[y][x*4:x*4+4])
  assert pixel(0,0)[3]==0
  r,g,b,a=pixel(30*scale,7*scale);assert a==255
  if name=='screenshot':assert b>r+80 and b>g
  elif name=='screen-recording':assert r>g+100 and r>b+80
  else:assert b>g+80 and r>g+20
  colors={tuple(row[i:i+4]) for row in rows for i in range(0,len(row),4)}
  assert len(colors)>100 and any(c[0]>245 and c[1]>245 and c[2]>245 and c[3]>245 for c in colors)
  hashes.append(hashlib.sha256(raw).hexdigest())
assert len(set(hashes))==3 and len(list(R.glob('*.png')))==3
print('Three default PNG assets decoded: correct dimensions, colored opaque background, transparent rounded corners, white glyph detail; no blank/template images')
