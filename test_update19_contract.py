from pathlib import Path
import re
R=Path(__file__).resolve().parent
ui=(R/'CenterChooser.swift').read_text()
session=(R/'CenterSelection.swift').read_text()
catalog=(R/'ChooserCatalog.m').read_text()
actions=(R/'SystemActions.m').read_text()
bridge=(R/'CenterChooserNative.S').read_text()
visibility=(R/'SystemVisibilityBridge.m').read_text()
policy=(R/'VisibilityPolicy.h').read_text()
native=(R/'native.S').read_text()
assert 'public func centerRingPan(' in ui
assert 'public func showChooserFromNativeSelection()' in ui
phase3=ui.split('if phase == 3 {',1)[1].split('guard let ring',1)[0]
assert 'session.didFinish()' in phase3 and 'selectCenter()' in phase3
assert 'STHChooserReadRing' not in phase3 and 's.scale' not in phase3
assert 'pan.location(in: pan.view)' in ui and 'gap * s.scale' not in ui
assert 'pan.state == .cancelled' in ui and 'pan.state == .failed' in ui
assert 'STHChooserSubmitCenterSelection()' in ui and 'STHChooserShowFromNativeSelection' in ui
assert 'STH_APP_CHOOSER_ID' in actions and 'STHChooserShowFromNativeSelection();' in actions
center=catalog.split('BOOL STHChooserSubmitCenterSelection(',1)[1]
assert 'STHChooserBuildManagerConsumed' in center and 'STHChooserOpenModelAnimated(model)' in center
assert 'STHChooserReleaseSwift(model)' in center
assert 'Color.white.brightness(state.hover ? 0.1 : -0.1)' in ui
assert 'state.hover ? 1.45 : 1' in ui and '-2.3 * last.iconWidth' in ui
assert 'transaction.disablesAnimations = true' in ui and '(open && !ringWasVisible)' in ui
assert 'if !tracking && snapshot.scale' not in ui
assert 'bl \\original' in bridge and 'mov w2,#2' in bridge and 'mov w2,#3' in bridge
assert 'STHVisibilitySample' in visibility and 'setterDepth' not in visibility # shared tested helper owns depth
assert 'STHHiddenSetterBegin' in visibility and 'forcedDepth' in visibility
assert 'value|latched' not in visibility and 'latched' not in visibility
assert 'isTransitioning' in visibility and 'STHVisibilityEvent' in visibility
assert '.35' in policy and 'if(!(known&bit))continue' in policy
initial=native.split('begin STHNativeInitialSize',1)[1]
assert initial.index('bl LresetSize')<initial.index('fmov d0,xzr')<initial.index('target 0x3f350')<initial.index('target 0x9c67c')
shared=native.split('LresetSize:',1)[1].split('begin STHNativeDock',1)[0]
assert 'target 0x3f350' not in shared
for p in R.iterdir():
 if p.suffix not in ('.m','.h','.inc','.S','.swift') or p.name.startswith('test'):continue
 text=p.read_text()
 for line in text.splitlines():
  if line.lstrip().startswith('//'):assert not re.search('[\u4e00-\u9fff]',line),(p.name,line)
 assert 'NSLog(' not in text and 'STHWriteLayoutLog' not in text,p.name
print('2.0.19: original ring auto-dismiss unchanged; release captured before collapse then ordinary admission; native App icon style; no opening translation; observed-state NC restore; fresh-model center only')
