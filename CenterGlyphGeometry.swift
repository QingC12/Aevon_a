import CoreGraphics
import Foundation

enum CenterGlyphGeometry {
    static func visibleHitArea(center: CGPoint, diameter: CGFloat, ringScale: CGFloat, liftedY: CGFloat, hover: Bool) -> CGRect {
        guard center.x.isFinite, center.y.isFinite, diameter.isFinite,
              ringScale.isFinite, liftedY.isFinite, diameter > 0, ringScale > 0 else { return .zero }
        let scale = ringScale * (hover ? 1.45 : 1)
        let width = diameter * scale
        let displayedCenter = CGPoint(x: center.x, y: center.y + liftedY * ringScale)
        return CGRect(x: displayedCenter.x - width / 2, y: displayedCenter.y - width / 2, width: width, height: width)
    }
}
