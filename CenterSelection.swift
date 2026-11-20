import Foundation

// The release decision is captured before native RingEnv cleanup. Delivery
// must not re-read collapsed scale, cleared selection or a terminal recognizer.
struct CenterSelectionSession {
    private(set) var active = false
    private(set) var hovered = false
    private var released = false

    mutating func begin() {
        active = true
        hovered = false
        released = false
    }
    mutating func update(candidate: Bool) {
        if !active { begin() }
        hovered = candidate
    }
    mutating func willFinish(candidate: Bool, cancelled: Bool) {
        released = candidate && !cancelled
        hovered = candidate && !cancelled
    }
    mutating func didFinish() -> Bool {
        let open = released
        active = false
        hovered = false
        released = false
        return open
    }
    mutating func cancel() {
        active = false
        hovered = false
        released = false
    }
}
