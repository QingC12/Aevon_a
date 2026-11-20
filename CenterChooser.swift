import SwiftUI
import UIKit
import QuartzCore

private final class CenterState: ObservableObject {
    @Published var origin = CGPoint.zero
    @Published var scale = 0.0
    @Published var diameter = 0.0
    @Published var hover = false
    @Published var drift = CGSize.zero
}
private struct CenterGlyph: View {
    @ObservedObject var state: CenterState
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(uiImage: STHAppChooserIcon(1)).resizable().scaledToFit()
                .padding(state.diameter * 0.15)
                .frame(width: state.diameter, height: state.diameter)
                .background(Color.primary.opacity(0.07)).clipShape(Circle())
        }
        .buttonStyle(.plain).scaleEffect(state.scale * (state.hover ? 1.15 : 1))
        .opacity(min(1, max(0, state.scale * 2 - 1))).offset(state.drift).position(state.origin)
        .accessibilityLabel("选择其他应用")
    }
}
private final class CenterSurface: UIView {
    var hitArea = CGRect.zero
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !isHidden && hitArea.contains(point)
    }
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
    @ObservedObject private var motion: PanelState
    init(items: [AppRow], state: PanelState, select: @escaping (String?) -> Void) {
        self.items = items; self.state = state; self.select = select; self.motion = state
    }
    private var matches: [AppRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q) }
    }
    var body: some View {
        ZStack {
            Color.black.opacity(motion.visible ? 0.18 : 0).ignoresSafeArea().onTapGesture { select(nil) }
            VStack(spacing: 14) {
                HStack {
                    Image(uiImage: STHAppChooserIcon(1)).resizable().frame(width: 32, height: 32).cornerRadius(8)
                    Text("打开应用").font(.title3.bold())
                    Spacer()
                    Button { select(nil) } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.title2) }
                }
                Text("仅显示未加入圆盘的应用").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("搜索应用", text: $query).autocorrectionDisabled().textInputAutocapitalization(.never)
                }.padding(12).background(Color.primary.opacity(0.06)).cornerRadius(12)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(matches) { app in
                            Button { select(app.id) } label: {
                                HStack(spacing: 14) {
                                    Image(uiImage: STHChooserAppIcon(app.id) ?? UIImage(systemName: "app")!).resizable().frame(width: 40, height: 40).cornerRadius(9)
                                    Text(app.name).foregroundColor(.primary).lineLimit(1)
                                    Spacer()
                                }.padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider().padding(.leading, 54)
                        }
                        if matches.isEmpty { Text("没有匹配的应用").foregroundColor(.secondary).padding(24) }
                    }
                }
            }.padding(20).frame(maxWidth: 390).frame(maxHeight: 560)
                .background(.regularMaterial).cornerRadius(26).padding(16)
                .scaleEffect(motion.visible ? 1 : 0.12).opacity(motion.visible ? 1 : 0)
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
    var scanAt = 0.0
    var suppressedUntil = 0.0
    var tracking = false
    var pending = false
    var last = STHChooserRingSnapshot()
    var wasOpen = false
    override init() {
        super.init()
        host = UIHostingController(rootView: CenterGlyph(state: state) { [weak self] in self?.openPanel() })
        host.view.backgroundColor = .clear
        surface.addSubview(host.view)
        surface.backgroundColor = .clear
        surface.isHidden = true
        display = CADisplayLink(target: self, selector: #selector(tick))
        display.preferredFramesPerSecond = 30
        display.add(to: .main, forMode: .common)
        NotificationCenter.default.addObserver(self, selector: #selector(systemChanged), name: Notification.Name("SthenoSystemVisibilityChanged"), object: nil)
    }
    private func containsHost(_ view: UIView, depth: Int = 0) -> Bool {
        guard depth < 8 else { return false }
        let name = NSStringFromClass(type(of: view))
        if name.contains("HostingView") && (name.contains("Stheno.Container") || name.contains("6Stheno9Container") || name == "_UIHostingView<Container>") { return true }
        return view.subviews.contains { containsHost($0, depth: depth + 1) }
    }
    private func findWindow(_ now: Double) {
        if let w = targetWindow, !w.isHidden { return }
        guard now - scanAt > 0.6 else { return }; scanAt = now
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for w in scene.windows where w !== panelWindow && containsHost(w) {
                targetWindow = w
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
        if blocked { tracking = false; pending = false; hidePanel(); surface.isHidden = true; return }
        last = snapshot
        guard let w = targetWindow else { return }
        let center = CGPoint(x: snapshot.portraitX + snapshot.offsetX, y: snapshot.portraitY + snapshot.offsetY)
        let p = surface.convert(center, from: UIScreen.main.fixedCoordinateSpace)
        let diameter = min(snapshot.iconWidth, 2 * snapshot.radius - snapshot.iconWidth - 4)
        guard diameter >= 20 else { surface.isHidden = true; return }
        surface.isHidden = snapshot.scale < 0.01
        surface.frame = w.bounds
        surface.hitArea = CGRect(x: p.x - diameter / 2, y: p.y - diameter / 2, width: diameter, height: diameter)
        let scaleChanged = abs(state.scale - snapshot.scale) > 0.0001
        let positionChanged = hypot(state.origin.x - p.x, state.origin.y - p.y) > 0.1
        if scaleChanged || (positionChanged && snapshot.gestureState == 2) {
            STHCenterRunAnimation({ self.state.origin = p; self.state.scale = snapshot.scale; self.state.diameter = diameter }, snapshot.scale <= 0 ? 1 : 0)
        } else if positionChanged || state.diameter != diameter {
            state.origin = p; state.diameter = diameter
        }
        surface.isUserInteractionEnabled = snapshot.scale > 0.5 && panelWindow == nil
        if !tracking && snapshot.scale < 0.1 && !wasOpen { hidePanel() }
    }
    func pan(_ ring: UnsafeMutableRawPointer?, _ recognizer: UnsafeMutableRawPointer?, phase: UInt32) {
        guard let ring, let recognizer, !STHSystemUIBlocked() else { return }
        let pan = Unmanaged<UIPanGestureRecognizer>.fromOpaque(recognizer).takeUnretainedValue()
        if phase == 0 { tracking = true; pending = false }
        guard tracking else { return }
        var s = STHChooserRingSnapshot()
        guard STHChooserReadRing(&s), s.editing == 0, s.quickSetting == 0, s.showTab == 0 else { tracking = false; return }
        let point = pan.view?.convert(pan.location(in: pan.view), to: UIScreen.main.fixedCoordinateSpace) ?? .zero
        let gap = max(0, min(s.iconWidth * 0.55, s.radius - 0.6 * s.iconWidth))
        let inside = hypot(point.x - s.portraitX - s.offsetX, point.y - s.portraitY - s.offsetY) <= gap * s.scale
        let selected = STHCenterRingSelected(ring)
        let hovered = inside && selected == 999 && s.scale > 0.5
        let drift = hovered ? CGSize(width: (point.x - s.portraitX - s.offsetX) * 0.18, height: (point.y - s.portraitY - s.offsetY) * 0.18) : .zero
        if state.hover != hovered || state.drift != drift {
            STHCenterRunAnimation({ self.state.hover = hovered; self.state.drift = drift }, 0)
        }
        if phase == 2 { pending = hovered && pan.state == .ended }
        if phase == 3 {
            tracking = false
            if pending { pending = false; DispatchQueue.main.async { self.openPanel() } }
        }
    }
    func openPanel() {
        guard panelWindow == nil, !STHSystemUIBlocked(), CACurrentMediaTime() >= suppressedUntil else { return }
        let rows = STHChooserSnapshotUnpinned() ?? []
        let items = rows.compactMap { row -> AppRow? in
            guard let id = row["identifier"], let name = row["name"] else { return nil }
            return AppRow(id: id, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard let scene = targetWindow?.windowScene else { return }
        let motion = PanelState(); panelState = motion; wasOpen = true
        previousKey = scene.windows.first(where: \.isKeyWindow)
        let w = UIWindow(windowScene: scene)
        w.frame = scene.coordinateSpace.bounds
        w.windowLevel = max((targetWindow?.windowLevel ?? .normal) + 1, .normal + 2)
        let controller = UIHostingController(rootView: AppPanel(items: items, state: motion) { [weak self] id in self?.closePanel(selecting: id) })
        controller.view.backgroundColor = .clear; w.rootViewController = controller
        panelWindow = w; w.makeKeyAndVisible()
        STHCenterRunAnimation({ motion.visible = true }, 0)
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
    @objc func systemChanged() { if STHSystemUIBlocked() { hidePanel(); surface.isHidden = true; tracking = false; pending = false } }
    func beforeCapture() { suppressedUntil = CACurrentMediaTime() + 1; hidePanel(); surface.isHidden = true; tracking = false; pending = false }
}
@_cdecl("STHInstallCenterChooser")
func installCenterChooser() { DispatchQueue.main.async { _ = CenterController.shared } }
@_cdecl("STHChooserHideBeforeCapture")
func hideCenterBeforeCapture() { CenterController.shared.beforeCapture() }
@_cdecl("STHCenterRingPan")
func centerRingPan(_ ring: UnsafeMutableRawPointer?, _ recognizer: UnsafeMutableRawPointer?, _ phase: UInt32) { CenterController.shared.pan(ring, recognizer, phase: phase) }
