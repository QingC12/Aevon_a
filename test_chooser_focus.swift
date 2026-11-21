import Foundation
@main struct TestChooserFocus {
    static func main() {
        for keyFirst in [false, true] {
            var policy = ChooserFocusPolicy(); policy.begin()
            assert(!policy.offer(appeared: false, attached: !keyFirst, key: keyFirst, active: true, blocked: false))
            assert(!policy.offer(appeared: true, attached: !keyFirst, key: keyFirst, active: true, blocked: false))
            assert(policy.offer(appeared: true, attached: true, key: true, active: true, blocked: false))
            assert(!policy.offer(appeared: true, attached: true, key: true, active: true, blocked: false))
            policy.close()
            assert(!policy.offer(appeared: true, attached: true, key: true, active: true, blocked: false))
        }
        var blocked = ChooserFocusPolicy(); blocked.begin()
        assert(!blocked.offer(appeared: true, attached: true, key: true, active: false, blocked: false))
        assert(!blocked.offer(appeared: true, attached: true, key: true, active: true, blocked: true))
        blocked.close()
        assert(!blocked.offer(appeared: true, attached: true, key: true, active: true, blocked: false))
        var reopened = ChooserFocusPolicy(); reopened.begin()
        assert(reopened.offer(appeared: true, attached: true, key: true, active: true, blocked: false))
        print("Chooser focus: event-driven key/attachment readiness, one offer per session, no focus after close")
    }
}
