import Foundation

// A center release is eligible only after this gesture crosses into the hole
// on purpose. The disc expands around the finger that summons it, so a finger
// already inside the hole when the disc finishes opening never entered it: it
// has to leave the hole and cross back in before a release can commit.
struct CenterSelectionSession {
    private(set) var active = false
    private(set) var hovered = false
    private var enteredCenter = false
    private var sawOutside = false
    private var released = false
    private var settled = false
    private var outsideAfterSettle = false

    mutating func begin() {
        active = true
        hovered = false
        enteredCenter = false
        sawOutside = false
        released = false
        settled = false
        outsideAfterSettle = false
    }
    // Called once the disc is fully open. `inside` is the finger position at
    // that moment: a finger already in the hole did not cross into it.
    mutating func settle(inside: Bool) {
        if !active { begin() }
        guard !settled else { return }
        settled = true
        outsideAfterSettle = !inside
    }
    mutating func update(inside: Bool, eligible: Bool, moved: Bool) {
        if !active { begin() }
        if !inside {
            sawOutside = true
            if settled { outsideAfterSettle = true }
            hovered = false
        } else if sawOutside && moved && eligible && settled && outsideAfterSettle {
            enteredCenter = true
            hovered = true
        } else {
            hovered = enteredCenter && eligible
        }
    }
    mutating func willFinish(inside: Bool, eligible: Bool, cancelled: Bool) {
        released = enteredCenter && inside && eligible && !cancelled
        hovered = released
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
        settled = false
        outsideAfterSettle = false
    }
}
