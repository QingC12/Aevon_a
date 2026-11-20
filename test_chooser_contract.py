from pathlib import Path
import io,tarfile,struct
R=Path(__file__).resolve().parent
catalog=(R/'ChooserCatalog.m').read_text();ui=(R/'CenterChooser.swift').read_text();state=(R/'ChooserState.m').read_text();native=(R/'ChooserNative.S').read_text()
for forbidden in ('setPersistentDomain','setObject:','STHSystemGrowApps','append','setValue:'):
 assert forbidden not in catalog,forbidden
for term in ('STHChooserCopyPinnedManagers','STHChooserCopyCatalogs','isVirtualAction','[pinned containsObject:identifier]','[seen containsObject:identifier]','STHChooserOpenModelAnimated(model)'):
 assert term in catalog,term
assert 'callcore 0x65af4' not in native # Original signed closure, not a normal C call.
assert 'mov x17,#0x720f' in native and 'callcore 0xaf19c' in native and 'callcore 0x4e024' in native
assert 'callcore 0x53e7c' in native and 'callcore 0x53f10' in native
assert 'STHCenterRunAnimation' in ui and 'selected == 999' in ui
assert 'hitArea.contains(point)' in ui and 'w.addSubview(surface)' in ui
assert 'fixedCoordinateSpace' in ui and 's.portraitX - s.offsetX' in ui
assert 'resultsHeight(matches.count, available: available)' in ui and '.frame(maxWidth: 360)' in ui
assert '@FocusState private var searchFocused: Bool' in ui
assert '.focused($searchFocused)' in ui and '.onChange(of: motion.visible)' in ui
assert 'private final class ChooserPanelWindow: UIWindow' in ui and 'override var canBecomeKey: Bool { true }' in ui
assert 'scene.activationState == .foregroundActive' in ui and 'w.makeKeyAndVisible()' in ui and 'w.makeKey()' in ui
assert 'state.drift' not in ui and 'state.lift' in ui
assert 'snapshot.editing' in ui and 'snapshot.quickSetting' in ui
center=(R/'CenterChooserNative.S').read_text()
assert 'STHCenterRingPan' in center and 'cc_call 0xaf19c' in center and 'cc_call 0xafb5c' in center
assert 'phase == 2' in center and 'bl \\original' in center
assert 'STHCenterRunAnimation({ self.state.hover = hovered; self.state.lift = lift }, 0)' in ui
assert '.offset(y: state.lift * CGFloat(state.scale))' in ui
assert 'STHChooserSubmitCenterSelection()' in ui and 'session.didFinish()' in ui
assert 'pan.location(in: pan.view)' in ui and 'gap * s.scale' not in ui
assert 'callcore 0x5421c' not in native # NOT a rings-array rebuild getter.
assert 'STHChooserHideBeforeCapture();' in (R/'SystemActions.m').read_text()
raw=(R/'inputs/base.deb').read_bytes();p=8;blob=None
while p<len(raw):
 h=raw[p:p+60];n=int(h[48:58]);name=h[:16].decode().strip().rstrip('/')
 if name=='data.tar.xz':blob=raw[p+60:p+60+n]
 p+=60+n+n%2
with tarfile.open(fileobj=io.BytesIO(blob)) as t:core=t.extractfile('./Library/MobileSubstrate/DynamicLibraries/Stheno.dylib').read()
for offset in (0x4e024,0x7ea40,0x65af4,0x58944,0x51454):assert core[offset:offset+4]==bytes.fromhex('7f2303d5'),hex(offset)
assert core[0x65b00:0x65b04]==bytes.fromhex('e00314aa') # original thunk passes context model as x0
print('Center chooser contract: original ring geometry untouched; real host passthrough; model-based animated visibility; native catalog minus pinned; transient original withAnimation launch; no preference writes')
