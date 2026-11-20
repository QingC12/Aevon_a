import Foundation

struct DockEntry: Equatable {
    let key: UInt
    let side: Int
    let height: Double
}
struct DockPlacement: Equatable {
    let key: UInt
    let centerY: Double
}
struct DockOrder {
    private(set) var left: [UInt] = []
    private(set) var right: [UInt] = []

    mutating func arrange(_ entries: [DockEntry], top: Double, bottom: Double) -> [DockPlacement] {
        let l = Set(entries.filter { $0.side == 0 }.map(\.key))
        let r = Set(entries.filter { $0.side == 1 }.map(\.key))
        left.removeAll { !l.contains($0) }
        right.removeAll { !r.contains($0) }
        for entry in entries {
            if entry.side == 0 && !left.contains(entry.key) { left.append(entry.key) }
            if entry.side == 1 && !right.contains(entry.key) { right.append(entry.key) }
        }
        let heights = Dictionary(entries.map { ($0.key, max(1, $0.height)) }, uniquingKeysWith: { a, _ in a })
        var result: [DockPlacement] = []
        for queue in [left, right] {
            let sum = queue.reduce(0.0) { $0 + (heights[$1] ?? 1) }
            let gap = queue.count > 1 ? min(10, max(0, (bottom - top - sum) / Double(queue.count - 1))) : 0
            var y = top
            for key in queue {
                let h = heights[key] ?? 1
                result.append(DockPlacement(key: key, centerY: y + h / 2))
                y += h + gap
            }
        }
        return result
    }
}

#if !STH_DOCK_TEST
private var order = DockOrder()

@_cdecl("STHDockSwiftReflow")
func reflowDock() {
    var entries: [DockEntry] = []
    let count = Int(STHDockCount())
    guard count >= 0 && count <= 4096 else { return }
    for i in 0..<count {
        var key: UInt = 0
        var side: Int32 = 0
        var height: Double = 0
        if STHDockRead(Int64(i), &key, &side, &height), key != 0, height.isFinite, height > 0 {
            entries.append(DockEntry(key: key, side: Int(side), height: height))
        }
    }
    for p in order.arrange(entries, top: STHDockTop(), bottom: STHDockBottom()) {
        STHDockApply(p.key, p.centerY)
    }
}
#endif
