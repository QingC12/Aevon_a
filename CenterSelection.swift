import Foundation

// A center release is eligible only after this gesture crosses into the hole.
struct CenterSelectionSession {
    private(set) var active = false
    private(set) var hovered = false
    private var enteredCenter = false
    private var sawOutside = false
    private var released = false

    mutating func begin() {
        active = true
        hovered = false
        enteredCenter = false
        sawOutside = false
        released = false
    }
    mutating func update(candidate: Bool, moved: Bool) {
        if !active { begin() }
        if !candidate {
            sawOutside = true
            hovered = false
        } else if sawOutside && moved {
            enteredCenter = true
            hovered = true
        } else {
            hovered = enteredCenter
        }
    }
    mutating func willFinish(candidate: Bool, cancelled: Bool) {
        released = enteredCenter && candidate && !cancelled
        hovered = enteredCenter && candidate && !cancelled
    }
    mutating func didFinish() -> Bool {
        let open = released
        reset()
        return open
    }
    mutating func cancel() { reset() }
    private mutating func reset() {
        active = false
        hovered = false
        enteredCenter = false
        sawOutside = false
        released = false
    }
}
