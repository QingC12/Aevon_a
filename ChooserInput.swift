import SwiftUI
import UIKit

final class ChooserInputSession: NSObject, ObservableObject {
    private var policy = ChooserFocusPolicy()
    private var appeared = false
    private var presented = false
    private weak var window: UIWindow?
    private weak var field: UITextField?
    private var assertion: NSObject?
    private var routingAttempted = false
    @Published private(set) var routingError: String?
    private var observations: [NSObjectProtocol] = []
    var invalidated: (() -> Void)?
    private(set) var closing = false

    func bind(_ window: UIWindow) {
        self.window = window
        policy.begin()
        STHKeyboardSetLocalInput(true)
        let center = NotificationCenter.default
        observations.append(center.addObserver(forName: UIWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in self?.offerFocus() })
        observations.append(center.addObserver(forName: UIWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in self?.invalidate() })
        observations.append(center.addObserver(forName: UIScene.willDeactivateNotification, object: window.windowScene, queue: .main) { [weak self] _ in self?.invalidate() })
        observations.append(center.addObserver(forName: UIScene.didDisconnectNotification, object: window.windowScene, queue: .main) { [weak self] _ in self?.invalidate() })
    }
    func attach(_ field: UITextField) { self.field = field; offerFocus() }
    func didAppear() { appeared = true; offerFocus() }
    func open() { presented = true; offerFocus() }
    func prepareRouting() -> Bool {
        guard !closing else { return false }
        if routingAttempted { return assertion != nil }
        guard let window, !window.isHidden,
              window.windowScene?.activationState == .foregroundActive else { return false }
        routingAttempted = true
        let acquired = STHAcquireChooserKeyboardFocus(window)
        guard !closing else {
            if let acquired { STHReleaseChooserKeyboardFocus(acquired) }
            return false
        }
        assertion = acquired
        if assertion == nil { routingError = "搜索键盘未取得系统输入焦点" }
        return assertion != nil
    }
    func allowEditing() -> Bool {
        guard presented, !closing, assertion != nil, let window, let field, field.window === window,
              window.windowScene?.activationState == .foregroundActive, window.isKeyWindow,
              !window.isHidden, !STHSystemUIBlocked() else { return false }
        return true
    }
    private func offerFocus() {
        guard let window, let field else { return }
        guard policy.offer(appeared: appeared && presented, attached: field.window === window,
                           key: window.isKeyWindow, active: window.windowScene?.activationState == .foregroundActive,
                           blocked: STHSystemUIBlocked(), routingReady: assertion != nil) else { return }
        guard allowEditing() else { return }
        // SpringBoard's focus assertion is acquired before UIKit requests its input view.
        if !field.isFirstResponder && !field.becomeFirstResponder() {
            routingError = "搜索输入框尚未取得响应焦点"
        }
    }
    func close() {
        guard !closing else { return }
        closing = true; policy.close()
        window?.endEditing(true)
        if let assertion { STHReleaseChooserKeyboardFocus(assertion) }
        assertion = nil
        for token in observations { NotificationCenter.default.removeObserver(token) }
        observations.removeAll()
    }
    func finish() { close(); STHKeyboardSetLocalInput(false); invalidated = nil }
    private func invalidate() { guard !closing else { return }; close(); invalidated?() }
    deinit {
        for token in observations { NotificationCenter.default.removeObserver(token) }
        if let assertion { STHReleaseChooserKeyboardFocus(assertion) }
    }
}

private final class ChooserTextField: UITextField {
    weak var inputSession: ChooserInputSession?
    override func didMoveToWindow() { super.didMoveToWindow(); inputSession?.attach(self) }
}
struct ChooserSearchField: UIViewRepresentable {
    @Binding var text: String
    let input: ChooserInputSession
    func makeCoordinator() -> Coordinator { Coordinator(text: $text, input: input) }
    func makeUIView(context: Context) -> UITextField {
        let field = ChooserTextField()
        field.placeholder = "搜索应用"
        field.autocorrectionType = .no; field.autocapitalizationType = .none
        field.returnKeyType = .search; field.clearButtonMode = .whileEditing
        field.backgroundColor = .clear
        field.delegate = context.coordinator; field.inputSession = input
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        input.attach(field)
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        if field.markedTextRange == nil && field.text != text { field.text = text }
    }
    static func dismantleUIView(_ field: UITextField, coordinator: Coordinator) { field.delegate = nil }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        let input: ChooserInputSession
        init(text: Binding<String>, input: ChooserInputSession) { self.text = text; self.input = input }
        @objc func changed(_ sender: UITextField) { text.wrappedValue = sender.text ?? "" }
        func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool { input.allowEditing() }
    }
}

final class ChooserHostingController<Content: View>: UIHostingController<Content> {
    let input: ChooserInputSession
    init(rootView: Content, input: ChooserInputSession) { self.input = input; super.init(rootView: rootView) }
    @MainActor required dynamic init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); input.didAppear() }
}
