import Foundation
@main struct TestChooserFocus {
    static func main() {
        for keyFirst in [false, true] {
            var policy = ChooserFocusPolicy(); policy.begin()
            assert(!policy.offer(appeared: true, attached: true, key: true, active: true, blocked: false, routingReady: false))
            assert(!policy.offered)
            assert(!policy.offer(appeared: false, attached: !keyFirst, key: keyFirst, active: true, blocked: false, routingReady: true))
            assert(!policy.offer(appeared: true, attached: !keyFirst, key: keyFirst, active: true, blocked: false, routingReady: true))
            assert(policy.offer(appeared: true, attached: true, key: true, active: true, blocked: false, routingReady: true))
            assert(!policy.offer(appeared: true, attached: true, key: true, active: true, blocked: false, routingReady: true))
            policy.close()
            assert(!policy.offer(appeared: true, attached: true, key: true, active: true, blocked: false, routingReady: true))
        }
        var blocked = ChooserFocusPolicy(); blocked.begin()
        assert(!blocked.offer(appeared: true, attached: true, key: true, active: false, blocked: false, routingReady: true))
        assert(!blocked.offer(appeared: true, attached: true, key: true, active: true, blocked: true, routingReady: true))
        blocked.close()
        assert(!blocked.offer(appeared: true, attached: true, key: true, active: true, blocked: false, routingReady: true))
        var reopened = ChooserFocusPolicy(); reopened.begin()
        assert(reopened.offer(appeared: true, attached: true, key: true, active: true, blocked: false, routingReady: true))
        print("Chooser focus: event-driven key/attachment readiness, one offer per session, no focus after close")
    }
}
