import Foundation
@main struct TestCenterSelection {
    static func main() {
        var session = CenterSelectionSession()

        session.begin()
        session.update(inside: false, eligible: false, moved: false)
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

        session.begin()
        session.update(inside: true, eligible: false, moved: false)
        session.update(inside: true, eligible: true, moved: true)
        assert(!session.hovered)
        session.willFinish(inside: true, eligible: true, cancelled: false)
        assert(!session.didFinish())

        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.willFinish(inside: false, eligible: false, cancelled: false)
        assert(!session.didFinish())

        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.update(inside: true, eligible: true, moved: true)
        session.willFinish(inside: true, eligible: true, cancelled: true)
        assert(!session.didFinish())

        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.update(inside: true, eligible: true, moved: false)
        session.willFinish(inside: true, eligible: true, cancelled: false)
        assert(!session.didFinish())

        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.update(inside: true, eligible: true, moved: true)
        session.update(inside: false, eligible: true, moved: true)
        session.willFinish(inside: false, eligible: true, cancelled: false)
        assert(!session.didFinish())

        session.begin()
        session.update(inside: false, eligible: false, moved: false)
        session.update(inside: true, eligible: true, moved: true)
        session.cancel()
        assert(!session.didFinish())

        for _ in 0..<100 {
            session.begin()
            session.update(inside: false, eligible: false, moved: false)
            session.update(inside: true, eligible: true, moved: true)
            session.willFinish(inside: true, eligible: true, cancelled: false)
            assert(session.didFinish())
        }
        print("Center release: only a deliberate outside-to-center crossing commits once")
    }
}
