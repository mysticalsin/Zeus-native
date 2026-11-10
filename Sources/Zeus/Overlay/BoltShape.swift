import SwiftUI

/// ZEUS's spark: a small lightning bolt, pointing up before rotation.
struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            CGPoint(x: 0.60, y: 0.00),
            CGPoint(x: 0.10, y: 0.58),
            CGPoint(x: 0.46, y: 0.58),
            CGPoint(x: 0.34, y: 1.00),
            CGPoint(x: 0.90, y: 0.38),
            CGPoint(x: 0.54, y: 0.38),
            CGPoint(x: 0.68, y: 0.00),
        ]
        var path = Path()
        for (index, point) in points.enumerated() {
            let scaled = CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
            if index == 0 { path.move(to: scaled) } else { path.addLine(to: scaled) }
        }
        path.closeSubpath()
        return path
    }
}
