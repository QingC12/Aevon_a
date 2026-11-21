import Foundation
struct ChooserFocusPolicy {
    private(set) var open = false
    private(set) var offered = false
    mutating func begin() { open = true; offered = false }
    mutating func close() { open = false; offered = true }
    mutating func offer(appeared: Bool, attached: Bool, key: Bool, active: Bool, blocked: Bool, routingReady: Bool) -> Bool {
        guard open, !offered, routingReady, appeared, attached, key, active, !blocked else { return false }
        offered = true
        return true
    }
}
