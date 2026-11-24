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
        .ignoresSafeArea()
    }
}
private final class CenterSurface: UIView {
    var hitArea = CGRect.zero
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !isHidden && UIBezierPath(ovalIn: hitArea).contains(point)
    }
}
private struct AppRow: Identifiable {
    let id: String
    let name: String
}
private final class PanelState: ObservableObject {
    @Published var visible = false
}
// The sheet uses a shape with rounded top corners only, so it sits flush on the
// bottom edge the way a native sheet does.
private struct ChooserSheet: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let corner = min(radius, min(rect.width, rect.height) * 0.5)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + corner))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: corner)
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: corner)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
private func chooserIcon(_ identifier: String) -> UIImage {
    if let icon = STHChooserAppIcon(identifier) { return icon }
    if let fallback = UIImage(systemName: "app.fill") { return fallback }
    return UIImage()
}
private struct ChooserPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
// The sheet lives in its own full screen window and deliberately ignores every safe
// area, including the keyboard one, so SwiftUI never moves it on its own. That is what
// let the keyboard cover the search bar: the sheet stayed pinned to the bottom edge.
// The observer below publishes the real keyboard overlap, which is used for one thing
// only: the strip of the grid that ends up behind the keyboard grows that much so the
// last row can still be scrolled clear. The sheet itself does not move for it.
private final class ChooserKeyboard: ObservableObject {
    @Published var overlap: CGFloat = 0
    private var tokens: [NSObjectProtocol] = []
    init() {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
            self?.apply(note, hidden: false)
        })
        tokens.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] note in
            self?.apply(note, hidden: true)
        })
    }
    private func apply(_ note: Notification, hidden: Bool) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        // The keyboard is always docked to the bottom edge on this target, so its own
        // height is exactly the height it hides of the sheet.
        let value = hidden ? 0 : max(0, frame.height)
        guard abs(value - overlap) > 0.5 else { return }
        let raw = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        withAnimation(.easeOut(duration: raw.map { min(max($0, 0.15), 0.4) } ?? 0.25)) { overlap = value }
    }
    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}
private struct AppPanel: View {
    let items: [AppRow]
    let state: PanelState
    let select: (String?) -> Void
    @State private var query = ""
    @ObservedObject var input: ChooserInputSession
    @ObservedObject private var motion: PanelState
    @StateObject private var keyboard = ChooserKeyboard()
    @Environment(\.colorScheme) private var scheme
    // Five equal flexible columns: every row splits the sheet width evenly, so the
    // icons sit on a uniform five way grid instead of drifting with the label widths.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 5)
    init(items: [AppRow], state: PanelState, input: ChooserInputSession, select: @escaping (String?) -> Void) {
        self.items = items; self.state = state; self.input = input; self.select = select; self.motion = state
    }
    private var matches: [AppRow] {
        items.filter { ChooserSearch.matches(query: query, name: $0.name, identifier: $0.id) }
    }
    private var caption: String {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "共 \(items.count) 个应用可选 · 未加入圆盘"
        }
        return "找到 \(matches.count) 个应用"
    }
    // The sheet has one height for a given screen and the keyboard must never change it.
    // A frame that animates its height re-lays out the lazy grid on every pass, and the
    // scroll view re-anchors while the sheet is still moving: that is what made the
    // panel wobble, slide out of place and then settle. The height is therefore a pure
    // function of the screen, and nothing about the keyboard feeds into it.
    private func sheetHeight(_ total: CGFloat) -> CGFloat {
        min(max(340, total * 0.62), 560)
    }
    // The keyboard belongs to the screen, not to the sheet: it floats above whatever is
    // already there, so the sheet keeps its height and its place while the keyboard sits
    // on top of its lower half. The sheet only nudges up when the keyboard is tall enough
    // to reach the search row, and then by exactly the handful of points that keeps that
    // row clear. Lifting it by the whole keyboard height pushed a 62% panel to the top
    // edge of the screen and made it read as a full screen page, which is not the shape
    // of a bottom drawer.
    private func lift(_ height: CGFloat) -> CGFloat {
        guard keyboard.overlap > 0 else { return 0 }
        // Distance from the sheet's top edge to the bottom of the search row, plus a
        // margin so the row never sits flush against the keyboard.
        let searchRowBottom: CGFloat = 112
        let margin: CGFloat = 8
        return min(keyboard.overlap, max(0, keyboard.overlap - height + searchRowBottom + margin))
    }
    var body: some View {
        GeometryReader { proxy in
            let total = proxy.size.height
            let height = sheetHeight(total)
            let raised = lift(height)
            ZStack(alignment: .bottom) {
                Color.black.opacity(scheme == .dark ? 0.55 : 0.26)
                    .contentShape(Rectangle())
                    .onTapGesture { select(nil) }
                sheet(height: height, covered: max(0, keyboard.overlap - raised))
                    .offset(y: motion.visible ? -raised : height + 30)
                    .opacity(motion.visible ? 1 : 0)
            }
            .ignoresSafeArea()
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: motion.visible)
        }
        // Without this the geometry would inherit the keyboard safe area and the sheet
        // height would shrink as the keyboard opens, which is the other half of the jump.
        .ignoresSafeArea()
    }
    private func sheet(height: CGFloat, covered: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(uiColor: .tertiaryLabel)).frame(width: 36, height: 5).padding(.top, 8)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("应用选择器").font(.system(size: 17, weight: .bold)).foregroundColor(Color(uiColor: .label))
                    Text(caption).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { select(nil) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(uiColor: .secondarySystemFill)))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 10)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                    ChooserSearchField(text: $query, input: input).frame(height: 22)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundColor(Color(uiColor: .tertiaryLabel))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(uiColor: .secondarySystemFill)))
                Button { select(nil) } label: {
                    Text("取消").font(.system(size: 13, weight: .semibold)).foregroundColor(.accentColor)
                }.buttonStyle(.plain)
            }
            .frame(height: 36)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.bottom, 8)
            if let error = input.routingError {
                Text(error).font(.system(size: 10)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 6)
            }
            grid(covered: covered)
        }
        .frame(height: height).frame(maxWidth: .infinity)
        .background(ChooserSheet(radius: 26).fill(Color(uiColor: .secondarySystemGroupedBackground)))
        .overlay(ChooserSheet(radius: 26).stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5))
        .clipShape(ChooserSheet(radius: 26))
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.5 : 0.16), radius: 26, x: 0, y: -8)
    }
    private func grid(covered: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            if matches.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 22, weight: .regular)).foregroundColor(Color(uiColor: .tertiaryLabel))
                    Text(items.isEmpty ? "没有未加入圆盘的应用" : "没有匹配的应用")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.top, 44)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(matches) { app in
                        Button { select(app.id) } label: { cell(app) }.buttonStyle(ChooserPressStyle())
                    }
                }
                .padding(.horizontal, 12).padding(.top, 8)
                // The sheet is tall enough that part of its lower edge can end up behind
                // the keyboard, so the run out grows by that covered strip and the last
                // row still scrolls clear. Padding only extends the scrollable extent,
                // it never moves a row, so nothing on screen shifts when it changes.
                .padding(.bottom, 30 + covered)
            }
        }
        .frame(maxHeight: .infinity)
    }
    private func cell(_ app: AppRow) -> some View {
        VStack(spacing: 6) {
            Image(uiImage: chooserIcon(app.id))
                .resizable().scaledToFit()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5))
            Text(app.name)
                .font(.system(size: 10))
                .foregroundColor(Color(uiColor: .label))
                .lineLimit(1).minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
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
    var panelInput: ChooserInputSession?
    var display: CADisplayLink!
    weak var targetWindow: UIWindow?
    weak var ringView: UIView?
    weak var gestureView: UIView?
    var scanAt = 0.0
    var needsHostScan = true
    var suppressedUntil = 0.0
    var session = CenterSelectionSession()
    var panStartPoint = CGPoint.zero
    var last = STHChooserRingSnapshot()
    var placementReady = false
    var ringWasVisible = false
    var presentationGeneration: UInt64 = 0
    var catalogRetry = 0
    var collapseUntil = 0.0
    var lastValidAt = 0.0
    var hasValidSnapshot = false
    override init() {
        super.init()
        host = UIHostingController(rootView: CenterGlyph(state: state) { [weak self] in self?.selectCenter() })
        host.view.backgroundColor = .clear
        surface.addSubview(host.view)
        surface.backgroundColor = .clear
        surface.isHidden = false
        host.view.isHidden = false
        surface.isUserInteractionEnabled = false
        display = CADisplayLink(target: self, selector: #selector(tick))
        display.preferredFramesPerSecond = 30
        display.add(to: .main, forMode: .common)
        NotificationCenter.default.addObserver(self, selector: #selector(systemChanged), name: Notification.Name("SthenoSystemVisibilityChanged"), object: nil)
        for name in [Notification.Name("UIWindowDidBecomeVisibleNotification"), Notification.Name("UIWindowDidBecomeHiddenNotification"), Notification.Name("UISceneDidActivateNotification"), Notification.Name("UIApplicationDidBecomeActiveNotification")] {
            NotificationCenter.default.addObserver(self, selector: #selector(lifecycleChanged), name: name, object: nil)
        }
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
    private func setGlyphVisible(_ visible: Bool) {
        if state.ready != visible { state.ready = visible }
        if !visible && state.lift != 0 { state.lift = 0 }
        let interactive = visible && panelWindow == nil && state.scale > 0.5
        if surface.isUserInteractionEnabled != interactive { surface.isUserInteractionEnabled = interactive }
        if host.view.isUserInteractionEnabled != interactive { host.view.isUserInteractionEnabled = interactive }
    }
    private func attach(to window: UIWindow, hostView: UIView) {
        targetWindow = window
        ringView = hostView
        surface.removeFromSuperview()
        surface.frame = window.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.frame = surface.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(surface)
        setGlyphVisible(false)
        surface.isUserInteractionEnabled = false
        needsHostScan = false
        hasValidSnapshot = false
        lastValidAt = 0
        placementReady = false
        ringWasVisible = false
        state.ready = false
        state.scale = 0
        state.lift = 0
        collapseUntil = 0
    }
    private func renderedCenter(_ native: CGPoint, in window: UIWindow) -> CGPoint {
        // RingEnv P+offset is in the display fixed portrait coordinate space.
        let screen = window.screen
        return surface.convert(native, from: screen.fixedCoordinateSpace)
    }
    private func sceneRank(_ scene: UIWindowScene) -> Int {
        switch scene.activationState {
        case .foregroundActive: return 4
        case .foregroundInactive: return 3
        case .background: return 2
        case .unattached: return 1
        @unknown default: return 0
        }
    }
    private func findWindow(_ now: Double) {
        if let w = targetWindow, !w.isHidden,
           let scene = w.windowScene,
           (scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive),
           surface.window === w {
            if !needsHostScan && now - scanAt < 0.5 { return }
            scanAt = now; needsHostScan = false
            if let currentHost = findHost(w), currentHost !== ringView {
                attach(to: w, hostView: currentHost)
            } else if findHost(w) == nil {
                targetWindow = nil; ringView = nil; session.cancel(); surface.hitArea = .zero
                setGlyphVisible(false)
            }
            return
        }
        if targetWindow != nil {
            session.cancel(); surface.hitArea = .zero; setGlyphVisible(false)
            ringWasVisible = false; placementReady = false
        }
        targetWindow = nil
        ringView = nil
        guard now - scanAt > 0.15 else { return }; scanAt = now
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
            .sorted { sceneRank($0) > sceneRank($1) }
        for scene in scenes {
            for w in scene.windows where w !== panelWindow && !w.isHidden && w.alpha > 0.01 {
                if let hostView = findHost(w) {
                    attach(to: w, hostView: hostView)
                    return
                }
            }
        }
    }
    @objc func tick() {
        STHRefreshSystemVisibility()
        let now = CACurrentMediaTime(); findWindow(now)
        var snapshot = STHChooserRingSnapshot()
        let enabled = STHSystemActionsEnabled()
        let valid = enabled && STHChooserReadRing(&snapshot)
        let systemBlocked = STHSystemUIBlocked() || now < suppressedUntil
        if valid { lastValidAt = now; hasValidSnapshot = true }
        if enabled && !valid && !systemBlocked && ringWasVisible && hasValidSnapshot && now - lastValidAt < 0.35 {
            surface.isUserInteractionEnabled = false
            host.view.isUserInteractionEnabled = false
            return
        }
        let blocked = !valid || systemBlocked || snapshot.editing != 0 || snapshot.quickSetting != 0 || snapshot.showTab != 0
        if blocked {
            session.cancel()
            if STHSystemUIBlocked() || now < suppressedUntil { hidePanel() }
            setGlyphVisible(false)
            updateHover(false)
            return
        }
        last = snapshot
        guard let w = targetWindow else { return }
        if surface.isHidden { surface.isHidden = false }
        surface.frame = w.bounds
        let nativeCenter = CGPoint(x: snapshot.portraitX + snapshot.offsetX, y: snapshot.portraitY + snapshot.offsetY)
        // Native P is in the display's fixed portrait coordinate space, not the Container's local space.
        let p = renderedCenter(nativeCenter, in: w)
        let diameter = min(snapshot.iconWidth, 2 * snapshot.radius - snapshot.iconWidth - 4)
        guard diameter >= 20 else { setGlyphVisible(false); return }
        let open = snapshot.scale > 0.01
        if !open {
            if ringWasVisible {
                collapseUntil = now + 0.15
                STHCenterRunAnimation({ self.state.scale = 0 }, 1)
                ringWasVisible = false
                setGlyphVisible(true)
            } else if now < collapseUntil {
                setGlyphVisible(true)
            } else {
                collapseUntil = 0
                setGlyphVisible(false)
                surface.hitArea = .zero
            }
            surface.isUserInteractionEnabled = false
            host.view.isUserInteractionEnabled = false
            return
        }
        collapseUntil = 0
        surface.hitArea = open ? CenterGlyphGeometry.visibleHitArea(center: p, diameter: diameter, ringScale: max(CGFloat(state.scale), CGFloat(snapshot.scale)), liftedY: state.lift, hover: state.hover) : .zero
        let scaleChanged = abs(state.scale - snapshot.scale) > 0.0001
        let positionChanged = hypot(state.origin.x - p.x, state.origin.y - p.y) > 0.1
        // Place before showing; start the native-parameter spring in this pan callback.
        if open && snapshot.gestureState == 2 && placementReady && ringWasVisible {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                state.origin = p; state.diameter = diameter
            }
            if scaleChanged { STHCenterRunAnimation({ self.state.scale = snapshot.scale }, 0) }
            setGlyphVisible(true)
        } else if !placementReady || (open && !ringWasVisible) {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                state.origin = p; state.diameter = diameter; state.scale = 0; state.ready = false
            }
            placementReady = true
            setGlyphVisible(open)
            if open {
                state.ready = true
                STHCenterRunAnimation({ self.state.scale = snapshot.scale }, 0)
            }
        } else {
            setGlyphVisible(open || state.scale >= 0.01)
            if open && !state.ready { state.ready = true }
            if scaleChanged || (positionChanged && snapshot.gestureState == 2) {
                STHCenterRunAnimation({ self.state.origin = p; self.state.scale = snapshot.scale; self.state.diameter = diameter }, snapshot.scale <= 0 ? 1 : 0)
            } else if positionChanged || state.diameter != diameter {
                state.origin = p; state.diameter = diameter
            }
        }
        ringWasVisible = open
        let interactive = snapshot.scale > 0.5 && panelWindow == nil
        surface.isUserInteractionEnabled = interactive
        host.view.isUserInteractionEnabled = interactive
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
        guard let sourceView = pan.view else { session.cancel(); updateHover(false); return }
        gestureView = sourceView
        if let window = sourceView.window, targetWindow !== window,
           let hostView = findHost(window) {
            attach(to: window, hostView: hostView)
        }
        if phase == 0 { session.begin(); tick() }
        var s = STHChooserRingSnapshot()
        guard STHChooserReadRing(&s), s.editing == 0, s.quickSetting == 0, s.showTab == 0 else { session.cancel(); updateHover(false); return }
        last = s
        let nativeCenter = CGPoint(x: s.portraitX + s.offsetX, y: s.portraitY + s.offsetY)
        guard let sourceWindow = sourceView.window else { session.cancel(); updateHover(false); return }
        let screen = sourceWindow.screen
        let centerInPan = sourceView.convert(nativeCenter, from: screen.fixedCoordinateSpace)
        let point = pan.location(in: sourceView)
        if phase == 0 { panStartPoint = point }
        let moved = hypot(point.x - panStartPoint.x, point.y - panStartPoint.y) >= 8
        let gap = max(0, s.radius - 0.6 * s.iconWidth)
        let inside = hypot(point.x - centerInPan.x, point.y - centerInPan.y) <= gap
        let selected = STHCenterRingSelected(ring)
        let eligible = selected == 999 && s.scale > 0.5 && gap > 0
        let cancelled = pan.state == .cancelled || pan.state == .failed
        // The disc opens around the summoning finger, so a finger that is
        // already in the hole when it finishes opening never crossed into it.
        if s.scale >= 0.98 { session.settle(inside: inside) }
        if phase == 2 {
            session.update(inside: inside && !cancelled, eligible: eligible, moved: moved)
            session.willFinish(inside: inside, eligible: eligible, cancelled: cancelled)
        } else {
            session.update(inside: inside && !cancelled, eligible: eligible, moved: moved)
        }
        updateHover(session.hovered)
        tick()
    }
    func selectCenter() {
        guard STHSystemActionsEnabled(), panelWindow == nil, !STHSystemUIBlocked(), CACurrentMediaTime() >= suppressedUntil else { return }
        _ = STHChooserSubmitCenterSelection()
    }
    func openPanel() {
        guard panelWindow == nil, !STHSystemUIBlocked(), CACurrentMediaTime() >= suppressedUntil else { catalogRetry = 0; return }
        findWindow(CACurrentMediaTime())
        guard let rows = STHChooserSnapshotUnpinned() else {
            catalogRetry += 1
            if catalogRetry <= 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.openPanel() }
            } else { catalogRetry = 0 }
            return
        }
        catalogRetry = 0
        let items = rows.compactMap { row -> AppRow? in
            guard let id = row["identifier"], let name = row["name"] else { return nil }
            return AppRow(id: id, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard let renderScene = targetWindow?.windowScene,
              let scene = STHChooserInputScene(renderScene), scene.activationState == .foregroundActive else { return }
        let motion = PanelState(); panelState = motion
        presentationGeneration &+= 1
        let generation = presentationGeneration
        previousKey = scene.windows.first(where: \.isKeyWindow)
        guard let w = STHCreateChooserInputWindow(scene) else { panelState = nil; return }
        let input = ChooserInputSession(); panelInput = input
        input.invalidated = { [weak self] in self?.hidePanel() }
        let controller = ChooserHostingController(rootView: AppPanel(items: items, state: motion, input: input) { [weak self] id in self?.closePanel(selecting: id) }, input: input)
        controller.view.backgroundColor = .clear; w.rootViewController = controller
        panelWindow = w; input.bind(w)
        w.isHidden = false
        guard panelWindow === w, !input.closing, !STHSystemUIBlocked() else { return }
        if input.prepareRouting() { w.makeKey() }
        guard panelWindow === w, panelState === motion, !input.closing else { return }
        controller.view.layoutIfNeeded()
        DispatchQueue.main.async {
            guard self.presentationGeneration == generation, self.panelState === motion, !STHSystemUIBlocked() else { return }
            guard self.panelWindow === w, !input.closing else { return }
            STHCenterRunAnimation({ motion.visible = true }, 0)
            input.open()
        }
    }
    func closePanel(selecting id: String?) {
        guard let motion = panelState, panelInput?.closing == false else { return }
        panelInput?.close()
        let generation = presentationGeneration
        STHCenterRunAnimation({ motion.visible = false }, 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard self.panelState === motion, self.presentationGeneration == generation else { return }
            self.hidePanel()
            if let id, !STHSystemUIBlocked() {
                STHSystemActionDismissRingNative(); STHSystemActionHideQuickSettingNative()
                _ = STHChooserSubmitFloating(id)
            }
        }
    }
    func hidePanel() {
        guard let window = panelWindow else { return }
        panelInput?.close()
        presentationGeneration &+= 1
        panelState = nil; panelWindow = nil
        let input = panelInput; panelInput = nil
        let restore = window.isKeyWindow
        window.endEditing(true); window.isHidden = true; window.rootViewController = nil
        if restore, let previousKey, !previousKey.isHidden,
           previousKey.windowScene === window.windowScene,
           previousKey.windowScene?.activationState == .foregroundActive {
            if window.windowScene?.windows.contains(where: { $0 !== window && $0.isKeyWindow }) != true { previousKey.makeKey() }
        }
        input?.finish()
        self.previousKey = nil
    }
    @objc func systemChanged() {
        scanAt = 0
        needsHostScan = true
        if STHSystemUIBlocked() {
            hidePanel(); setGlyphVisible(false); session.cancel(); ringWasVisible = false; placementReady = false; updateHover(false)
        }
    }
    @objc func lifecycleChanged() {
        scanAt = 0
        needsHostScan = true
        if targetWindow == nil || surface.window == nil { setGlyphVisible(false) }
    }
    func beforeCapture() {
        suppressedUntil = CACurrentMediaTime() + 1; hidePanel(); setGlyphVisible(false); session.cancel(); ringWasVisible = false; placementReady = false; updateHover(false)
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
