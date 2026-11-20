import Foundation
@main struct TestDockQueue {
    static func main() {
        var order = DockOrder()
        let a = DockEntry(key: 1, side: 0, height: 90)
        let b = DockEntry(key: 2, side: 0, height: 90)
        let c = DockEntry(key: 3, side: 1, height: 100)
        var result = order.arrange([a,b,c], top: 40, bottom: 800)
        assert(order.left == [1,2] && order.right == [3])
        assert(result[0].centerY == 85 && result[1].centerY == 185)
        result = order.arrange([b,c], top: 40, bottom: 800)
        assert(order.left == [2] && result[0].centerY == 85)
        _ = order.arrange([a,b,c], top: 40, bottom: 800)
        assert(order.left == [2,1])
        _ = order.arrange([DockEntry(key: 2, side: 1, height: 90),a,c], top: 40, bottom: 800)
        assert(order.left == [1] && order.right == [3,2])
        for _ in 0..<100 { _ = order.arrange([a,c], top: 40, bottom: 800) }
        assert(order.left == [1] && order.right == [3])
        _ = order.arrange([], top: 40, bottom: 800)
        assert(order.left.isEmpty && order.right.isEmpty)
        print("Dock queues: independent sides; newest appended; restore/removal compacts; stable repeated reflow")
    }
}
