import Foundation
import CoreGraphics

@main struct TestCenterGlyphGeometry {
    static func main() {
        let center = CGPoint(x: 518, y: 445)
        let normal = CenterGlyphGeometry.visibleHitArea(center: center, diameter: 80, ringScale: 1, liftedY: 0, hover: false)
        assert(normal.contains(center))
        assert(abs(normal.midX - 518) < 0.01 && abs(normal.midY - 445) < 0.01)
        let hover = CenterGlyphGeometry.visibleHitArea(center: center, diameter: 80, ringScale: 0.8, liftedY: -138, hover: true)
        assert(abs(hover.width - 80 * 0.8 * 1.45) < 0.01)
        assert(abs(hover.midY - (445 - 138 * 0.8)) < 0.01)
        assert(hover.contains(CGPoint(x: hover.midX, y: hover.midY)))
        assert(CenterGlyphGeometry.visibleHitArea(center: center, diameter: 80, ringScale: .nan, liftedY: 0, hover: false).isEmpty)
        print("Center glyph hit geometry follows rendered scale, hover lift and center")
    }
}
