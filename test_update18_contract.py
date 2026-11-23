from pathlib import Path
import re,ast,hashlib,json
R=Path(__file__).resolve().parent
build=ast.parse((R/'build.py').read_text())
for name in ['CenterChooser.swift','DockQueue.swift','CenterChooserNative.S','DockQueueNative.S','SystemVisibilityBridge.m']:
 assert (R/name).exists(),name
frozen=json.loads((R/'inputs/base-patched.json').read_text())
assert frozen['update18']['original_animation_transactions'] is True
swift=(R/'CenterChooser.swift').read_text();native=(R/'CenterChooserNative.S').read_text();dock=(R/'DockQueueNative.S').read_text();visibility=(R/'SystemVisibilityBridge.m').read_text()
assert 'STHCenterRunAnimation' in swift and 'phase == 2' in swift and 'phase == 3' in swift
assert 'pan.state == .cancelled' in swift and 'selected == 999' in swift
assert 'state.drift' not in swift and '2.3 * last.iconWidth' in swift
for value in ['0x51454','0xafb5c','0xaf19c']:
 assert value in dock and value in native,value
for value in ['SBControlCenterController','SBCoverSheetPresentationManager','SBLockScreenManager','SthenoSystemVisibilityChanged','STHVisibilitySample']:
 assert value in visibility,value
assert 'UIStatusBarWindow' not in visibility
assert 'busSet(c->commit' in (R/'ViewportBus.m').read_text()
for p in R.iterdir():
 if p.suffix not in ('.m','.h','.inc','.swift','.S') or p.name.startswith('test'):continue
 text=p.read_text()
 for line in text.splitlines():
  if line.lstrip().startswith('//'):assert not re.search('[\u4e00-\u9fff]',line),(p.name,line)
 assert 'STHWriteLayoutLog' not in text and 'NSLog(' not in text and 'SthenoKeyboardLayout.log' not in text,p.name
assert len(list((R/'resources/system-actions').glob('*.png')))==3
for name in ['NotificationPolicy.m','LayoutProbe.m','LayoutProbe.h','ChooserUI.m','ChooserPanel.m']:
 assert not (R/name).exists(),name
print('2.0.18 contract: native same-finger chooser; SwiftUI original transactions; separate docking queues; system-page gate; no incremental diagnostic emitters; three default icons; English comments')
