import Foundation

/// Drop of the closed top bar, and the physical screen-edge outline the glow and the wave hug.
/// This type does not read a screen, a pointer, a clock, or a stored setting.
public enum TopBarPositionBox {
    public static let minimum = 0.0
    public static let maximum = 24.0
    public static let step = 2.0

    /// How far the edge light sits inside the physical screen.
    public static let edgeInset = 2.0
    /// The corner radius before the half outline clamps it.
    public static let edgeRadius = 12.0

    public struct Outline: Equatable, Sendable {
        public var centerX: Double
        public var top: Double
        public var right: Double
        public var bottom: Double
        public var radius: Double

        public init(centerX: Double, top: Double, right: Double, bottom: Double, radius: Double) {
            self.centerX = centerX
            self.top = top
            self.right = right
            self.bottom = bottom
            self.radius = radius
        }
    }

    /// Finite, on the step, and inside 0...24. A value that is not finite reads as no drop.
    public static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return minimum }
        let snapped = (value / step).rounded() * step
        return min(max(snapped, minimum), maximum)
    }

    /// What was stored, or no drop when nothing was chosen.
    public static func resolved(chosen: Double?) -> Double {
        chosen.map(clamped) ?? minimum
    }

    /// The open panel sits flush with the top. Only a closed bar keeps its drop.
    public static func applied(resolved: Double, panelOpen: Bool) -> Double {
        panelOpen ? minimum : clamped(resolved)
    }

    /// The right half of a screen edge, in the overlay's coordinates (origin top-left, y down).
    /// A size, inset, or radius that is not finite reads as zero. The radius never exceeds the room
    /// the half outline can hold.
    public static func outline(
        width: Double, height: Double, inset: Double = edgeInset, radius: Double = edgeRadius
    ) -> Outline {
        let w = width.isFinite ? max(0, width) : 0
        let h = height.isFinite ? max(0, height) : 0
        let i = inset.isFinite ? max(0, inset) : 0
        let centerX = w / 2
        let top = i
        let right = max(centerX, w - i)
        let bottom = max(i, h - i)
        let room = min(right - centerX, (bottom - top) / 2)
        let fitted = max(0, min(radius.isFinite ? radius : 0, room))
        return Outline(centerX: centerX, top: top, right: right, bottom: bottom, radius: fitted)
    }
}
