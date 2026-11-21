"""Source/packaging boundaries only; UIKit layout correctness needs device data."""
from pathlib import Path
import json,re
R=Path(__file__).resolve().parent
retired=json.loads((R/'inputs/viewport31-retirement.json').read_text())
for name in retired['production']+retired['tests']:
 assert not (R/name).exists(),('Retired implementation survived',name)
client=(R/'ViewportClient.m').read_text();host=(R/'ViewportHost.m').read_text();build=(R/'build.py').read_text();dispatch=(R/'dispatch.S').read_text();native=(R/'native.S').read_text()
for source in [client,host]:
 for pattern in [r'\.transform\s*=',r'\.frame\s*=',r'\.bounds\s*=',r'\.center\s*=',r'\.contentInset\s*=',r'\.additionalSafeAreaInsets\s*=',r'\.text\b']:
  assert not re.search(pattern,source),('A leaf/container is being rewritten',pattern)
for old in ['STHNativeKeyboardShow','STHNativeKeyboardHide','STHNativeSetKeyboardGeometry','_original_keyboard_show_plus4','_original_keyboard_hide_target']:
 assert old not in native+dispatch+host+client,old
for old in ['KeyboardCoordinates.m','KeyboardInset.m','EditorGuard.m','LayoutPublisher.m','KeyboardFocusBus.m']:
 assert "'"+old+"'" not in build,old
assert "changes[0x8778c]=(bytes.fromhex('e80200f0'),0x87964)" in build
assert 'changes[0x87b8c]' not in build and 'changes[0x87dfc]' not in build
assert 'STHCenterRunAnimation' in host and 'writeCard' in host
assert 'STHVAuthoritativeMap' in client and 'STHVInset' in client
assert 'toCoordinateSpace:scene.screen.coordinateSpace' in client
assert 'toCoordinateSpace:scene.screen.fixedCoordinateSpace' in client
assert 'firstWill' in client and 'predictionSerial' in client and 'client-host-inactive' in client
assert 'STHVResumeRequest' in client and 'STHVPublishRequest(bundle(),YES' in client
assert 'manualOverride' in host and host.index('maintainOwner(nativeTransaction)')<host.index('void *array=STHDockCopyFloating()')
assert 'sbPhysicalGeneration' in host and 'request.event' in host and 'request.keyboard' not in host
assert 'appRawDiagnostic' in client and 'noDockedKeyboard' in host and 'STHVPublishLayoutPolicyState' in host
assert 'STHVClientHidden' in client and 'explicitHidden' in client and 'return 0;' in client
assert 'STHGestureInputFocusChanged' in host
assert 'STHVViewport' not in host
print('Viewport32 contract: 36 legacy production sources retired; original avoidance registration disabled; no editor transforms; canonical scene/screen bridge; original spring; bounded cleanup; fresh owner and real-event fencing')
