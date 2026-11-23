import Foundation
@main struct TestCenterSelection {
    static func main() {
        var session = CenterSelectionSession()

        // A crossing made after the disc is fully open commits exactly once.
        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.settle(inside: false)
        assert(!session.hovered)
        session.update(inside: true, eligible: true, moved: false)
        assert(!session.hovered)
        session.update(inside: true, eligible: true, moved: true)
        assert(session.hovered)
        session.update(inside: false, eligible: true, moved: true)
        assert(!session.hovered)
        session.update(inside: true, eligible: true, moved: true)
        assert(session.hovered)
        session.willFinish(inside: true, eligible: true, cancelled: false)
        assert(session.didFinish())
        assert(!session.didFinish())

        // Summoning the disc: it expands around the finger, so the finger is
        // already in the hole when it opens. Releasing there must not commit.
        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.update(inside: true, eligible: true, moved: true)
        assert(!session.hovered)
        session.settle(inside: true)
        session.update(inside: true, eligible: true, moved: true)
        assert(!session.hovered)
        session.willFinish(inside: true, eligible: true, cancelled: false)
        assert(!session.didFinish())

        // The same summon becomes a deliberate selection once the finger
        // leaves the hole and crosses back in.
        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.update(inside: true, eligible: true, moved: true)
        session.settle(inside: true)
        session.update(inside: false, eligible: true, moved: true)
        session.update(inside: true, eligible: true, moved: true)
        assert(session.hovered)
        session.willFinish(inside: true, eligible: true, cancelled: false)
        assert(session.didFinish())

        // Settling while the finger is outside arms the very next crossing.
        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.settle(inside: false)
        session.update(inside: true, eligible: true, moved: true)
        assert(session.hovered)
        session.willFinish(inside: true, eligible: true, cancelled: false)
        assert(session.didFinish())

        // Settling is idempotent: a later settle must not disarm the crossing.
        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.settle(inside: true)
        session.update(inside: false, eligible: true, moved: true)
        session.settle(inside: true)
        session.update(inside: true, eligible: true, moved: true)
        assert(session.hovered)
        session.willFinish(inside: true, eligible: true, cancelled: false)
        assert(session.didFinish())

        // Not settled at all: no crossing can commit.
        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.update(inside: true, eligible: true, moved: true)
        session.willFinish(inside: true, eligible: true, cancelled: false)
        assert(!session.didFinish())

        // Entering before the disc opens does not survive as a commit.
        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.update(inside: true, eligible: true, moved: true)
        session.settle(inside: false)
        session.willFinish(inside: true, eligible: true, cancelled: false)
        assert(!session.didFinish())

        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.settle(inside: false)
        session.willFinish(inside: false, eligible: false, cancelled: false)
        assert(!session.didFinish())

        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.settle(inside: false)
        session.update(inside: true, eligible: true, moved: true)
        session.willFinish(inside: true, eligible: true, cancelled: true)
        assert(!session.didFinish())

        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.settle(inside: false)
        session.update(inside: true, eligible: true, moved: false)
        session.willFinish(inside: true, eligible: true, cancelled: false)
        assert(!session.didFinish())

        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.settle(inside: false)
        session.update(inside: true, eligible: true, moved: true)
        session.update(inside: false, eligible: true, moved: true)
        session.willFinish(inside: false, eligible: true, cancelled: false)
        assert(!session.didFinish())

        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.settle(inside: false)
        session.update(inside: true, eligible: true, moved: true)
        session.cancel()
        assert(!session.didFinish())

        for _ in 0..<100 {
            session.begin()
            session.update(inside: false, eligible: false, moved: false)
            session.settle(inside: false)
            session.update(inside: true, eligible: true, moved: true)
            session.willFinish(inside: true, eligible: true, cancelled: false)
            assert(session.didFinish())
        }
        print("Center release: only a deliberate post-open outside-to-center crossing commits once")
    }
}
