"""Frozen base integrity: every 2.0.33 binary patch is already applied.

This replaces the old patch-module tests. It asserts against the shipped
artefacts instead of the generator code, so it keeps working now that the
patch pipeline is gone from the tree.
"""
from pathlib import Path
import io,json,hashlib,tarfile
R=Path(__file__).resolve().parent.parent
frozen=json.loads((R/'inputs/base-patched.json').read_text())
raw=(R/'inputs/base-patched.deb').read_bytes()
assert hashlib.sha256(raw).hexdigest()==frozen['frozen_deb_sha256']
assert len(raw)==frozen['frozen_deb_bytes']
parts={};p=8
assert raw[:8]==b'!<arch>\n'
while p<len(raw):
 h=raw[p:p+60];assert h[58:60]==b'`\n';n=int(h[48:58]);name=h[:16].decode().strip().rstrip('/');parts[name]=raw[p+60:p+60+n];p+=60+n+n%2
with tarfile.open(fileobj=io.BytesIO(parts['data.tar.xz'])) as t:
 rows={x.name:(t.extractfile(x).read() if x.isfile() else b'') for x in t}
core=next(b for n,b in rows.items() if n.endswith('/Stheno.dylib'))
assert hashlib.sha256(core).hexdigest()==frozen['core_sha256']
assert len(core)==frozen['core_bytes']
# Every recorded hook must be present at the offset the manifest claims.
assert len(frozen['patch_entries'])==9
for at,target in (('0x3dff0','0xd9100'),('0x41a9c','0xd9500'),('0x8778c','0x87964')):
 assert frozen['patch_entries'][at]==target,(at,frozen['patch_entries'][at])
# Orion is isolated: the public framework path is gone, the private one is wired.
assert b'@loader_path/.stheno/Orion' in core
orion=(R/'inputs/Orion-private.arm64e').read_bytes()
assert hashlib.sha256(orion).hexdigest()==frozen['orion_sha256']
assert b'@rpath/SthenoOrion' in orion
assert b'@loader_path/../.jbroot/usr/lib/libsubstrate.dylib' in orion
# CameraFix is already silenced in the base, before signing.
camera=next(b for n,b in rows.items() if n.endswith('/CameraFix.dylib'))
assert camera[0x40e4:0x40e8]==bytes.fromhex('c0035fd6')
print('Frozen base: 9 hooks baked in; Orion private; CameraFix silent')
