import SwiftUI
import UIKit
import QuartzCore

private final class CenterState: ObservableObject {
    @Published var origin = CGPoint.zero
    @Published var scale = 0.0
    @Published var diameter = 0.0
    @Published var ready = false
    @Published var hover = false
    @Published var lift: CGFloat = 0
}
private struct CenterGlyph: View {
    @ObservedObject var state: CenterState
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(uiImage: STHAppChooserIcon(1)).resizable().scaledToFit()
                .padding(state.diameter * 0.15)
                .frame(width: state.diameter, height: state.diameter)
                .background(Color.white.brightness(state.hover ? 0.1 : -0.1)).clipShape(Circle())
        }
        .buttonStyle(.plain).scaleEffect(state.scale * (state.hover ? 1.45 : 1))
        .opacity(state.ready ? min(1, max(0, state.scale * 2 - 1)) : 0).offset(y: state.lift * CGFloat(state.scale)).position(state.origin)
        .zIndex(state.hover ? 1 : 0)
        .accessibilityLabel("选择其他应用")
    }
}
private final class CenterSurface: UIView {
    var hitArea = CGRect.zero
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !isHidden && hitArea.contains(point)
    }
}
private final class ChooserPanelWindow: UIWindow {
    override var canBecomeKey: Bool { true }
}
private struct AppRow: Identifiable {
    let id: String
    let name: String
}
private final class PanelState: ObservableObject {
    @Published var visible = false
}
private struct AppPanel: View {
    let items: [AppRow]
    let state: PanelState
    let select: (String?) -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @ObservedObject private var motion: PanelState
    init(items: [AppRow], state: PanelState, select: @escaping (String?) -> Void) {
        self.items = items; self.state = state; self.select = select; self.motion = state
    }
    private var matches: [AppRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q) }
    }
    private func resultsHeight(_ count: Int, available: CGFloat) -> CGFloat {
        if count == 0 { return 48 }
        let reserved = available > 300 ? 180 : 150
        let cap = max(36, min(244, available - CGFloat(reserved)))
        return min(CGFloat(count) * 61, cap)
    }
    var body: some View {
        GeometryReader { geometry in
            let available = max(180, geometry.size.height - 24)
            ZStack {
                Color.black.opacity(motion.visible ? 0.18 : 0).ignoresSafeArea().onTapGesture { select(nil) }
                VStack(spacing: available > 300 ? 10 : 8) {
                    HStack {
                        Image(uiImage: STHAppChooserIcon(1)).resizable().frame(width: 32, height: 32).cornerRadius(8)
                        Text("打开应用").font(.title3.bold())
                        Spacer()
                        Button { select(nil) } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.title2) }
                    }
                    if available > 300 {
                        Text("仅显示未加入圆盘的应用").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("搜索应用", text: $query).autocorrectionDisabled().textInputAutocapitalization(.never).focused($searchFocused)
                    }.padding(12).background(Color.primary.opacity(0.06)).cornerRadius(12)
                    if matches.isEmpty {
                        Text("没有匹配的应用").foregroundColor(.secondary).frame(maxWidth: .infinity).frame(height: 48)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(matches) { app in
                                    Button { select(app.id) } label: {
                                        HStack(spacing: 14) {
                                            Image(uiImage: STHChooserAppIcon(app.id) ?? UIImage(systemName: "app")!).resizable().frame(width: 40, height: 40).cornerRadius(9)
                                            Text(app.name).foregroundColor(.primary).lineLimit(1)
                                            Spacer()
                                        }.frame(height: 60).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    Divider().padding(.leading, 54)
                                }
                            }
                        }.frame(height: resultsHeight(matches.count, available: available))
                    }
                }.padding(16).frame(maxWidth: 360)
                    .background(.regularMaterial).cornerRadius(24)
                    .fixedSize(horizontal: false, vertical: true)
                    .scaleEffect(motion.visible ? 1 : 0.12).opacity(motion.visible ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .onChange(of: motion.visible) { visible in
            DispatchQueue.main.async { searchFocused = visible }
        }
    }
}

private final class CenterController: NSObject {
    static let shared = CenterController()
    let state = CenterState()
    let surface = CenterSurface()
    var host: UIHostingController<CenterGlyph>!
    var panelWindow: UIWindow?
    weak var previousKey: UIWindow?
    var panelState: PanelState?
    var display: CADisplayLink!
    weak var targetWindow: UIWindow?
    weak var ringView: UIView?
    var scanAt = 0.0
    var suppressedUntil = 0.0
    var session = CenterSelectionSession()
    var panStartPoint = CGPoint.zero
    var last = STHChooserRingSnapshot()
    var placementReady = false
    var ringWasVisible = false
    var presentationGeneration: UInt64 = 0
    override init() {
        super.init()
        host = UIHostingController(rootView: CenterGlyph(state: state) { [weak self] in self?.selectCenter() })
        host.view.backgroundColor = .clear
        surface.addSubview(host.view)
        surface.backgroundColor = .clear
        surface.isHidden = true
        display = CADisplayLink(target: self, selector: #selector(tick))
        display.preferredFramesPerSecond = 30
        display.add(to: .main, forMode: .common)
        NotificationCenter.default.addObserver(self, selector: #selector(systemChanged), name: Notification.Name("SthenoSystemVisibilityChanged"), object: nil)
    }
    private func findHost(_ view: UIView, depth: Int = 0) -> UIView? {
        guard depth < 8 else { return nil }
        let name = NSStringFromClass(type(of: view))
        if name.contains("HostingView") && (name.contains("Stheno.Container") || name.contains("6Stheno9Container") || name == "_UIHostingView<Container>") { return view }
        for child in view.subviews {
            if let found = findHost(child, depth: depth + 1) { return found }
        }
        return nil
    }
    private func containsHost(_ view: UIView, depth: Int = 0) -> Bool {
        findHost(view, depth: depth) != nil
    }
    private func findWindow(_ now: Double) {
        if let w = targetWindow, !w.isHidden { return }
        guard now - scanAt > 0.6 else { return }; scanAt = now
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for w in scene.windows where w !== panelWindow && containsHost(w) {
                targetWindow = w
                ringView = findHost(w)
                surface.removeFromSuperview(); surface.frame = w.bounds
                surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                host.view.frame = surface.bounds; host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                w.addSubview(surface); STHRegisterSthenoSurface(surface); return
            }
        }
    }
    @objc func tick() {
        STHRefreshSystemVisibility()
        let now = CACurrentMediaTime(); findWindow(now)
        var snapshot = STHChooserRingSnapshot()
        let valid = STHSystemActionsEnabled() && STHChooserReadRing(&snapshot)
        let blocked = !valid || STHSystemUIBlocked() || snapshot.editing != 0 || snapshot.quickSetting != 0 || snapshot.showTab != 0 || now < suppressedUntil
        if blocked {
            session.cancel()
            if STHSystemUIBlocked() || now < suppressedUntil { hidePanel() }
            surface.isHidden = true
            return
        }
        last = snapshot
        guard let w = targetWindow else { return }
        surface.frame = w.bounds
        let center = CGPoint(x: snapshot.portraitX + snapshot.offsetX, y: snapshot.portraitY + snapshot.offsetY)
        // RingEnv and the recognizer use the same host-local portrait space.
        // Convert from that view instead of applying a second screen rotation.
        let p = ringView.map { surface.convert(center, from: $0) } ??
            surface.convert(center, from: UIScreen.main.fixedCoordinateSpace)
        let diameter = min(snapshot.iconWidth, 2 * snapshot.radius - snapshot.iconWidth - 4)
        guard diameter >= 20 else { surface.isHidden = true; return }
        let open = snapshot.scale > 0.01
        surface.frame = w.bounds
        surface.hitArea = CGRect(x: p.x - diameter / 2, y: p.y - diameter / 2, width: diameter, height: diameter)
        let scaleChanged = abs(state.scale - snapshot.scale) > 0.0001
        let positionChanged = hypot(state.origin.x - p.x, state.origin.y - p.y) > 0.1
        // Place before showing; start the native-parameter spring in this pan callback.
        if open && snapshot.gestureState == 2 && placementReady && ringWasVisible {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                state.origin = p; state.diameter = diameter
            }
            surface.isHidden = false
        } else if !placementReady || (!open && positionChanged) || (open && !ringWasVisible) {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                state.origin = p; state.diameter = diameter; state.scale = 0; state.ready = false
            }
            placementReady = true
            surface.isHidden = !open
            if open {
                state.ready = true
                STHCenterRunAnimation({ self.state.scale = snapshot.scale }, 0)
            }
        } else {
            surface.isHidden = !open && state.scale < 0.01
            if open && !state.ready { state.ready = true }
            if scaleChanged || (positionChanged && snapshot.gestureState == 2) {
                STHCenterRunAnimation({ self.state.origin = p; self.state.scale = snapshot.scale; self.state.diameter = diameter }, snapshot.scale <= 0 ? 1 : 0)
            } else if positionChanged || state.diameter != diameter {
                state.origin = p; state.diameter = diameter
            }
        }
        ringWasVisible = open
        surface.isUserInteractionEnabled = snapshot.scale > 0.5 && panelWindow == nil
    }
    func updateHover(_ hovered: Bool) {
        let lift: CGFloat = hovered ? CGFloat(-2.3 * last.iconWidth) : 0
        if state.hover != hovered || state.lift != lift {
            STHCenterRunAnimation({ self.state.hover = hovered; self.state.lift = lift }, 0)
        }
    }
    func pan(_ ring: UnsafeMutableRawPointer?, _ recognizer: UnsafeMutableRawPointer?, phase: UInt32) {
        // Do not consult native scale/selection after finish: native end has
        // already collapsed the carrier and cleared those values.
        if phase == 3 {
            let shouldOpen = session.didFinish()
            updateHover(false)
            if shouldOpen { selectCenter() }
            return
        }
        guard let ring, let recognizer, !STHSystemUIBlocked() else { session.cancel(); return }
        let pan = Unmanaged<UIPanGestureRecognizer>.fromOpaque(recognizer).takeUnretainedValue()
        if let sourceView = pan.view { ringView = sourceView }
        if phase == 0 { session.begin(); tick() }
        var s = STHChooserRingSnapshot()
        guard STHChooserReadRing(&s), s.editing == 0, s.quickSetting == 0, s.showTab == 0 else { session.cancel(); updateHover(false); return }
        last = s
        // The original RingEnv samples in recognizer.view's portrait space.
        // An additional fixed-screen conversion changes the hit coordinates.
        let point = pan.location(in: pan.view)
        if phase == 0 { panStartPoint = point }
        let moved = hypot(point.x - panStartPoint.x, point.y - panStartPoint.y) >= 8
        let gap = max(0, s.radius - 0.6 * s.iconWidth)
        let inside = hypot(point.x - s.portraitX - s.offsetX, point.y - s.portraitY - s.offsetY) <= gap
        let selected = STHCenterRingSelected(ring)
        let candidate = inside && selected == 999 && s.scale > 0.5
        let cancelled = pan.state == .cancelled || pan.state == .failed
        if phase == 2 {
            session.update(candidate: candidate && !cancelled, moved: moved)
            session.willFinish(candidate: candidate, cancelled: cancelled)
        } else {
            session.update(candidate: candidate && !cancelled, moved: moved)
        }
        updateHover(session.hovered)
        tick()
    }
    func selectCenter() {
        guard STHSystemActionsEnabled(), panelWindow == nil, !STHSystemUIBlocked(), CACurrentMediaTime() >= suppressedUntil else { return }
        _ = STHChooserSubmitCenterSelection()
    }
    func openPanel() {
        guard panelWindow == nil, !STHSystemUIBlocked(), CACurrentMediaTime() >= suppressedUntil else { return }
        let rows = STHChooserSnapshotUnpinned() ?? []
        let items = rows.compactMap { row -> AppRow? in
            guard let id = row["identifier"], let name = row["name"] else { return nil }
            return AppRow(id: id, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard let scene = targetWindow?.windowScene, scene.activationState == .foregroundActive else { return }
        let motion = PanelState(); panelState = motion
        presentationGeneration &+= 1
        let generation = presentationGeneration
        previousKey = scene.windows.first(where: \.isKeyWindow)
        let w = ChooserPanelWindow(windowScene: scene)
        w.frame = scene.coordinateSpace.bounds
        w.windowLevel = max((targetWindow?.windowLevel ?? .normal) + 1, .normal + 2)
        let controller = UIHostingController(rootView: AppPanel(items: items, state: motion) { [weak self] id in self?.closePanel(selecting: id) })
        controller.view.backgroundColor = .clear; w.rootViewController = controller
        panelWindow = w; w.isHidden = false; w.makeKeyAndVisible(); controller.view.layoutIfNeeded()
        DispatchQueue.main.async {
            guard self.presentationGeneration == generation, self.panelState === motion, !STHSystemUIBlocked() else { return }
            if !w.isKeyWindow { w.makeKey() }
            STHCenterRunAnimation({ motion.visible = true }, 0)
        }
    }
    func closePanel(selecting id: String?) {
        guard let motion = panelState else { return }
        STHCenterRunAnimation({ motion.visible = false }, 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard self.panelState === motion else { return }
            self.hidePanel()
            if let id, !STHSystemUIBlocked() {
                STHSystemActionDismissRingNative(); STHSystemActionHideQuickSettingNative()
                _ = STHChooserSubmitFloating(id)
            }
        }
    }
    func hidePanel() {
        guard let window = panelWindow else { return }
        panelState = nil; panelWindow = nil
        let restore = window.isKeyWindow; window.endEditing(true); window.isHidden = true; window.rootViewController = nil
        if restore, let previousKey, !previousKey.isHidden { previousKey.makeKey() }
        self.previousKey = nil
    }
    @objc func systemChanged() {
        if STHSystemUIBlocked() { hidePanel(); surface.isHidden = true; session.cancel(); ringWasVisible = false; updateHover(false) }
    }
    func beforeCapture() {
        suppressedUntil = CACurrentMediaTime() + 1; hidePanel(); surface.isHidden = true; session.cancel(); ringWasVisible = false; updateHover(false)
    }
}
@_cdecl("STHInstallCenterChooser")
public func installCenterChooser() { DispatchQueue.main.async { _ = CenterController.shared } }
@_cdecl("STHChooserHideBeforeCapture")
public func hideCenterBeforeCapture() { CenterController.shared.beforeCapture() }
@_cdecl("STHCenterRingPan")
public func centerRingPan(_ ring: UnsafeMutableRawPointer?, _ recognizer: UnsafeMutableRawPointer?, _ phase: UInt32) { CenterController.shared.pan(ring, recognizer, phase: phase) }

@_cdecl("STHChooserShowFromNativeSelection")
public func showChooserFromNativeSelection() { CenterController.shared.openPanel() }
