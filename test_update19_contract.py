from pathlib import Path
import re,json
R=Path(__file__).resolve().parent
ui=(R/'CenterChooser.swift').read_text()
session=(R/'CenterSelection.swift').read_text()
catalog=(R/'ChooserCatalog.m').read_text()
actions=(R/'SystemActions.m').read_text()
bridge=(R/'CenterChooserNative.S').read_text()
visibility=(R/'SystemVisibilityBridge.m').read_text()
policy=(R/'VisibilityPolicy.h').read_text()
assert 'public func centerRingPan(' in ui
assert 'public func showChooserFromNativeSelection()' in ui
phase3=ui.split('if phase == 3 {',1)[1].split('guard let ring',1)[0]
assert 'session.didFinish()' in phase3 and 'selectCenter()' in phase3
assert 'STHChooserReadRing' not in phase3 and 's.scale' not in phase3
assert 'pan.location(in: sourceView)' in ui and 'sourceView.convert(nativeCenter, from: screen.fixedCoordinateSpace)' in ui
assert 'pan.state == .cancelled' in ui and 'pan.state == .failed' in ui
assert 'STHChooserSubmitCenterSelection()' in ui and 'STHChooserShowFromNativeSelection' in ui
assert 'STH_APP_CHOOSER_ID' in actions and 'STHChooserShowFromNativeSelection();' in actions
center=catalog.split('BOOL STHChooserSubmitCenterSelection(',1)[1]
assert 'STHChooserBuildManagerConsumed' in center and 'STHChooserOpenModelAnimated(model)' in center
assert 'STHChooserReleaseSwift(model)' in center
assert 'Color.white.brightness(state.hover ? 0.1 : -0.1)' in ui
assert 'state.hover ? 1.45 : 1' in ui and '2.3 * last.iconWidth' in ui
assert 'self.state.lift = lift' in ui and 'state.lift * CGFloat(state.scale)' in ui
assert 'session.update(inside: inside && !cancelled, eligible: eligible, moved: moved)' in ui
assert 'session.willFinish(inside: inside, eligible: eligible, cancelled: cancelled)' in ui
assert 'STHNativeMinimized' in (R/'Gesture.m').read_text() and 'pendingRehit' in (R/'Gesture.m').read_text()
assert 'finishGestureState(s)' in (R/'Gesture.m').read_text()
chooserNative=(R/'ChooserNative.S').read_text()
assert 'STHChooserClearMinimized' in chooserNative
assert 'transaction.disablesAnimations = true' in ui and '(open && !ringWasVisible)' in ui
assert 'if !tracking && snapshot.scale' not in ui
assert 'bl \\original' in bridge and 'mov w2,#2' in bridge and 'mov w2,#3' in bridge
assert 'STHVisibilitySample' in visibility and 'setterDepth' not in visibility # shared tested helper owns depth
assert 'STHHiddenSetterBegin' in visibility and 'forcedDepth' in visibility
assert 'value|latched' not in visibility and 'latched' not in visibility
assert 'isTransitioning' in visibility and 'STHVisibilityEvent' in visibility
assert '.35' in policy and 'if(!(known&bit))continue' in policy
bridges=json.loads((R/'inputs/base-patched.json').read_text())['native_bridges']
assert '_STHNativeInitialSize' in bridges['exports']
assert bridges['base']<=bridges['exports']['_STHNativeInitialSize']<bridges['end']
assert 'LresetSize' in bridges['callbacks']
assert bridges['original_callbacks']=={'dock':0x4D4C4,'initializer':0x4FF20}
assert 0<bridges['size']<=bridges['capacity'] and bridges['end']==bridges['base']+bridges['size']
for p in R.iterdir():
 if p.suffix not in ('.m','.h','.inc','.S','.swift') or p.name.startswith('test'):continue
 text=p.read_text()
 for line in text.splitlines():
  if line.lstrip().startswith('//'):assert not re.search('[\u4e00-\u9fff]',line),(p.name,line)
 assert 'NSLog(' not in text and 'STHWriteLayoutLog' not in text,p.name
print('2.0.24: center geometry follows native pan basis; stale gesture recovery; dock restore; Unicode app search; key-gated UIKit input')
