from pathlib import Path
import io,tarfile,struct
R=Path(__file__).resolve().parent.parent
catalog=(R/'ChooserCatalog.m').read_text();ui=(R/'CenterChooser.swift').read_text();state=(R/'ChooserState.m').read_text();native=(R/'ChooserNative.S').read_text()
for forbidden in ('setPersistentDomain','setObject:','STHSystemGrowApps','append','setValue:'):
 assert forbidden not in catalog,forbidden
for term in ('STHChooserCopyPinnedManagers','STHChooserCopyCatalogs','isVirtualAction','[pinned containsObject:identifier]','[seen containsObject:identifier]','STHChooserOpenModelAnimated(model)'):
 assert term in catalog,term
assert 'callcore 0x65af4' not in native # Original signed closure, not a normal C call.
assert 'mov x17,#0x720f' in native and 'callcore 0xaf19c' in native and 'callcore 0x4e024' in native
assert 'callcore 0x53e7c' in native and 'callcore 0x53f10' in native
assert 'STHCenterRunAnimation' in ui and 'selected == 999' in ui
assert 'UIBezierPath(ovalIn: hitArea).contains(point)' in ui and 'w.addSubview(surface)' in ui
assert 'surface.convert(native, from: screen.fixedCoordinateSpace)' in ui and 'renderedCenter(nativeCenter, in: w)' in ui
assert 'CenterGlyphGeometry.visibleHitArea' in ui and 'liftedY: state.lift' in ui
assert 'state.scale = snapshot.scale' in ui
# The picker is a bottom sheet with a six column icon grid: the whole catalog is
# browsable at once instead of one tall row at a time, and the sheet keeps only its
# own surfaces so the system light/dark appearance drives every colour.
assert 'ChooserSheet(radius: 26)' in ui and 'func path(in rect: CGRect) -> Path' in ui
assert 'LazyVGrid(columns: columns, spacing: 12)' in ui and 'count: 6' in ui
assert 'LazyVStack(spacing: 0)' not in ui and 'resultsHeight' not in ui
assert 'Color(uiColor: .secondarySystemGroupedBackground)' in ui
assert 'Color(uiColor: .secondarySystemFill)' in ui and 'Color(uiColor: .label)' in ui
assert 'scheme == .dark ? 0.55 : 0.26' in ui
assert 'offset(y: motion.visible ? 0 : height + 30)' in ui
assert '.animation(.spring(response: 0.34, dampingFraction: 0.88), value: motion.visible)' in ui
assert 'ChooserPressStyle()' in ui and 'minimumScaleFactor(0.7)' in ui
inputSource=(R/'ChooserInput.swift').read_text()
inputNative=(R/'ChooserInputNative.m').read_text()
assert 'ChooserSearchField(text: $query, input: input)' in ui
assert 'ChooserSearch.matches(query: query, name: $0.name, identifier: $0.id)' in ui
assert 'field.markedTextRange == nil' in inputSource
# A bottom sheet must not summon the keyboard on its own: the keyboard would push the
# sheet up and hide most of the grid. Focus is requested only from the search field.
assert 'guard searchRequested' in inputSource and 'func allowSearchEditing() -> Bool' in inputSource
assert 'textFieldShouldBeginEditing' in inputSource and 'input.allowSearchEditing()' in inputSource
assert 'viewDidAppear' in inputSource and 'didMoveToWindow' in inputSource
assert 'window.isKeyWindow' in inputSource and 'field.window === window' in inputSource
routing=(R/'ChooserFocusRouting.inc').read_text()
assert 'requestFocusStealingForSpringBoardWindow:forReason:' in routing and 'lockFocusToSpringBoardWindowScene:forReason:' in routing
assert 'STHChooserInputScene(renderScene)' in ui and 'activeDisplayWindowSceneFollowingUserInteraction' in inputNative
assert 'SBFWindow' in inputNative and 'STHReleaseChooserKeyboardFocus' in inputSource
assert 'scene.activationState == .foregroundActive' in ui and 'if input.prepareRouting() { w.makeKey() }' in ui
assert 'panelInput?.close()' in ui and 'input.open()' in ui
assert 'routingReady: assertion != nil' in inputSource and 'assertion != nil, let window' in inputSource
assert 'reloadInputViews' not in inputSource and 'UIWindow.didResignKeyNotification' in inputSource
assert 'private func invalidate() { guard !closing else' in inputSource and 'if let acquired { STHReleaseChooserKeyboardFocus(acquired) }' in inputSource
assert 'private func attach(to window: UIWindow, hostView: UIView)' in ui
assert 'surface.window === w' in ui and 'sceneRank' in ui and 'lifecycleChanged' in ui
assert 'host.view.isHidden = !visible' not in ui
assert 'state.ready = visible' in ui and 'if surface.isHidden { surface.isHidden = false }' in ui
assert 'ringView = sourceView' not in ui and 'gestureView = sourceView' in ui
assert 'host.view.isUserInteractionEnabled = interactive' in ui and 'UIWindow.didBecomeKeyNotification' in inputSource
assert 'attempts < 20' not in inputSource and 'previousKey.windowScene === window.windowScene' in ui
assert 'state.drift' not in ui and 'state.lift' in ui
assert 'snapshot.editing' in ui and 'snapshot.quickSetting' in ui
center=(R/'CenterChooserNative.S').read_text()
assert 'STHCenterRingPan' in center and 'cc_call 0xaf19c' in center and 'cc_call 0xafb5c' in center
assert 'phase == 2' in center and 'bl \\original' in center
assert 'STHCenterRunAnimation({ self.state.hover = hovered; self.state.lift = lift }, 0)' in ui
assert '.offset(y: state.lift * CGFloat(state.scale))' in ui
assert 'STHChooserSubmitCenterSelection()' in ui and 'session.didFinish()' in ui
selection=(R/'CenterSelection.swift').read_text()
# Summoning the disc expands it around the finger: a center release only commits
# after the disc is fully open and the finger crosses back into the hole.
assert 'mutating func settle(inside: Bool)' in selection and 'outsideAfterSettle' in selection
assert 'if s.scale >= 0.98 { session.settle(inside: inside) }' in ui
assert 'sawOutside && moved && eligible && settled && outsideAfterSettle' in selection
assert 'pan.location(in: sourceView)' in ui and 'sourceView.convert(nativeCenter, from: screen.fixedCoordinateSpace)' in ui
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
