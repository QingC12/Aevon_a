import Foundation
@main struct TestCenterSelection {
    static func main() {
        var session = CenterSelectionSession()

        session.begin()
        session.update(candidate: false, moved: false)
        assert(!session.hovered)
        session.update(candidate: true, moved: false)
        assert(!session.hovered)
        session.update(candidate: true, moved: true)
        assert(session.hovered)
        session.update(candidate: false, moved: true)
        assert(!session.hovered)
        session.update(candidate: true, moved: true)
        assert(session.hovered)
        session.willFinish(candidate: true, cancelled: false)
        assert(session.didFinish())
        assert(!session.didFinish())

        session.begin()
        session.update(candidate: true, moved: false)
        session.willFinish(candidate: true, cancelled: false)
        assert(!session.didFinish())

        session.begin()
        session.update(candidate: false, moved: false)
        session.willFinish(candidate: false, cancelled: false)
        assert(!session.didFinish())

        session.begin()
        session.update(candidate: false, moved: false)
        session.update(candidate: true, moved: true)
        session.willFinish(candidate: true, cancelled: true)
        assert(!session.didFinish())

        session.begin()
        session.update(candidate: false, moved: false)
        session.update(candidate: true, moved: false)
        session.willFinish(candidate: true, cancelled: false)
        assert(!session.didFinish())

        session.begin()
        session.update(candidate: false, moved: false)
        session.update(candidate: true, moved: true)
        session.update(candidate: false, moved: true)
        session.willFinish(candidate: false, cancelled: false)
        assert(!session.didFinish())

        session.begin()
        session.update(candidate: false, moved: false)
        session.update(candidate: true, moved: true)
        session.cancel()
        assert(!session.didFinish())

        for _ in 0..<100 {
            session.begin()
            session.update(candidate: false, moved: false)
            session.update(candidate: true, moved: true)
            session.willFinish(candidate: true, cancelled: false)
            assert(session.didFinish())
        }
        print("Center release: only a deliberate outside-to-center crossing commits once")
    }
}
