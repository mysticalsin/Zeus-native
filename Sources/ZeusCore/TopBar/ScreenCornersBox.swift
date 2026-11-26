import Foundation

/// Bottom-corner squares for a notched display.
/// Screen frames use an origin at the bottom left, with y up. Mask points use the corner square's own
/// coordinates, origin at the top left, with y down. This type does not read a screen, a pointer, or a clock.
public enum ScreenCornersBox {
    public enum Side: String, CaseIterable, Sendable {
        case bottomLeft
        case bottomRight
    }

    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public static let zero = Rect(x: 0, y: 0, width: 0, height: 0)
    }

    public struct Frames: Equatable, Sendable {
        public var radius: Double
        public var bottomLeft: Rect
        public var bottomRight: Rect

        public init(radius: Double, bottomLeft: Rect, bottomRight: Rect) {
            self.radius = radius
            self.bottomLeft = bottomLeft
            self.bottomRight = bottomRight
        }

        public func rect(for side: Side) -> Rect {
            switch side {
            case .bottomLeft: bottomLeft
            case .bottomRight: bottomRight
            }
        }
    }

    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Finite, never negative, and never more than a quarter of the shorter side.
    public static func clampedRadius(_ radius: Double, width: Double, height: Double) -> Double {
        guard radius.isFinite, radius > 0,
              width.isFinite, height.isFinite, width > 0, height > 0 else { return 0 }
        return min(radius, min(width, height) / 4)
    }

    /// The bottom-left and bottom-right squares. A radius that does not fit reads as two zero rectangles.
    public static func cornerFrames(
        x: Double, y: Double, width: Double, height: Double, radius: Double
    ) -> Frames {
        let fitted = clampedRadius(radius, width: width, height: height)
        guard fitted > 0 else { return Frames(radius: 0, bottomLeft: .zero, bottomRight: .zero) }
        return Frames(
            radius: fitted,
            bottomLeft: Rect(x: x, y: y, width: fitted, height: fitted),
            bottomRight: Rect(x: x + width - fitted, y: y, width: fitted, height: fitted)
        )
    }

    /// Inside the square and not inside the quarter disc. The arc itself counts as filled.
    public static func fills(x: Double, y: Double, side: Side, radius: Double) -> Bool {
        guard radius.isFinite, radius > 0, x.isFinite, y.isFinite,
              x >= 0, x <= radius, y >= 0, y <= radius else { return false }
        let centre = discCentre(side, radius: radius)
        return hypot(x - centre.x, y - centre.y) >= radius
    }

    /// Closed outline of the filled region: the screen corner first, then the arc.
    /// Fewer than two segments still draws the two ends and one step between them.
    public static func maskPoints(side: Side, radius: Double, segments: Int = 16) -> [Point] {
        guard radius.isFinite, radius > 0 else { return [] }
        let steps = max(2, segments)
        let centre = discCentre(side, radius: radius)
        let corner = Point(x: side == .bottomLeft ? 0 : radius, y: radius)
        var points = [corner]
        for step in 0...steps {
            let angle = Double.pi - (Double.pi / 2) * Double(step) / Double(steps)
            let dx = radius * cos(angle)
            let px = side == .bottomLeft ? centre.x + dx : centre.x - dx
            points.append(Point(x: px, y: centre.y + radius * sin(angle)))
        }
        return points
    }

    /// The disc centre is the square's inner corner, opposite the screen corner.
    private static func discCentre(_ side: Side, radius: Double) -> Point {
        switch side {
        case .bottomLeft: Point(x: radius, y: 0)
        case .bottomRight: Point(x: 0, y: 0)
        }
    }
}
