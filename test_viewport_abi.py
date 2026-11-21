"""Final-image evidence for the reset; not a device keyboard/animation test."""
from pathlib import Path
import json,struct,sys,plistlib
from test_published_bridge_abi import Image,calls
from embed_orion import exports
R=Path(__file__).resolve().parent
folder=Path(sys.argv[1]) if len(sys.argv)>1 else R/'build'
m=json.loads((folder/'build-manifest.json').read_text())
core=Image(folder/'Stheno.dylib');action=Image(folder/'SthenoSystemActions.dylib');client=Image(folder/'SthenoViewport.dylib')
assert core.data[0x8778c:0x87790]==bytes.fromhex('76000014'),'Original keyboard observers still registered'
assert core.data[0x87b8c:0x87b90]==bytes.fromhex('7f2303d5')
assert core.data[0x87dfc:0x87e00]==bytes.fromhex('843e0114')
core.symbols.update(m['native_bridges']['exports'])
assert len(m['native_bridges']['exports'])==21
setter=[target for target,_ in calls(core.words('_STHNativeSetViewportGeometry'),core.symbols['_STHNativeSetViewportGeometry'])]
assert setter==[0x9e3b0,0x3f350],list(map(hex,setter))
classifier=[target for target,_ in calls(core.words('_STHNativeClassify'),core.symbols['_STHNativeClassify'])]
assert classifier==[0xd781c],list(map(hex,classifier))
words=action.words('_STHCenterRunAnimation')
assert [a for a,_ in calls(words,action.symbols['_STHCenterRunAnimation'])]==[0x51454,0x51454,0xafb5c,0xafb4c,0xaf19c,0xb0a0c]
assert 0x1e616801 not in words,'Custom damping floor returned'
for image in [action,client]:
 names=exports(image.data)
 for old in ['_STHKeyboardShow','_STHKeyboardHide','_STHNativeKeyboardShow','_STHNativeKeyboardHide','_STHNativeSetKeyboardGeometry','_STHLayoutStatus','_STHEditorVisibilityEvent','_STHCardRunExpansion']:
  assert old not in names,('Legacy callback exported',old)
assert {'_STHViewportPhysicalWill','_STHViewportSetLocalInput','_STHViewportModelMinimized','_STHGestureInputFocusChanged'}<=exports(action.data)
assert {'_STHVPublishRequest','_STHVResumeRequest','_STHVReadLayout'}<=exports(client.data)
print('Viewport31 ARM64e ABI: original avoidance observers skipped, old callbacks absent, 21 utility bridges, physical hit filter replaces stale legacy cache, original spring targets unchanged, standalone new client exports complete')
