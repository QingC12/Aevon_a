import Foundation
@main struct TestCenterSelection {
    static func main() {
        var session = CenterSelectionSession()
        session.begin()
        session.update(candidate: true)
        assert(session.hovered)
        session.willFinish(candidate: true, cancelled: false)
        // Native end now collapses scale and clears selected. Delivery must
        // consume the earlier decision without asking those values again.
        assert(session.didFinish())
        assert(!session.didFinish())
        session.begin(); session.update(candidate: true)
        session.willFinish(candidate: false, cancelled: false)
        assert(!session.didFinish())
        session.begin(); session.update(candidate: true)
        session.willFinish(candidate: true, cancelled: true)
        assert(!session.didFinish())
        session.update(candidate: true)
        session.willFinish(candidate: true, cancelled: false)
        assert(session.didFinish())
        session.begin(); session.update(candidate: true); session.cancel()
        assert(!session.didFinish())
        for _ in 0..<100 {
            session.begin(); session.update(candidate: true)
            session.willFinish(candidate: true, cancelled: false)
            assert(session.didFinish())
        }
        print("Center release: latched before native collapse, one ordinary admission, cancel/leave/repeat protected")
    }
}
