import Foundation

/// S2: rounded bottom screen corners. A notched display has rounded top corners and square bottom ones;
/// an optional overlay of two tiny black shapes rounds the bottom pair to match. Pure geometry here (no
/// AppKit) so it is unit-testable; `ScreenCornerOverlay` (Sources/Zeus/Notch) owns the panels.
///
/// Two coordinate systems are used. Frames are in screen coordinates (AppKit: origin bottom-left, y up,
/// negative origins allowed for displays left of or below the main one). The mask is in the corner
/// square's own coordinates (origin top-left, y down), which is what a drawing canvas uses.

/// The three corner sizes Settings offers. Anything else reads as Medium.
public enum ScreenCornerSize: CaseIterable, Sendable {
    case small, medium, large

    public init(label: String) {
        switch label.trimmingCharacters(in: .whitespaces).lowercased() {
        case "small": self = .small
        case "large": self = .large
        default: self = .medium
        }
    }

    /// The Settings choice text.
    public var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// Corner radius in points.
    public var radius: Double {
        switch self {
        case .small: 8
        case .medium: 12
        case .large: 18
        }
    }
}

public enum ScreenCornerSide: CaseIterable, Sendable {
    case bottomLeft, bottomRight
}

/// The two corner squares of one screen, in screen coordinates. `radius` is the size after clamping.
public struct ScreenCornerFrames: Equatable, Sendable {
    public let radius: Double
    public let bottomLeft: CGRect
    public let bottomRight: CGRect

    public func frame(for side: ScreenCornerSide) -> CGRect {
        switch side {
        case .bottomLeft: bottomLeft
        case .bottomRight: bottomRight
        }
    }
}

public enum ScreenCorners {
    /// Corners are drawn only on a display that has a notch (only those have rounded top corners), and only
    /// while the setting is on.
    public static func draws(hasNotch: Bool, enabled: Bool) -> Bool {
        hasNotch && enabled
    }

    /// A notch shows as a top safe-area inset with a menu bar area on each side of it. An empty or missing
    /// area (the app passes 0) is not a notch.
    public static func hasNotch(safeAreaTop: Double, leftAreaWidth: Double, rightAreaWidth: Double) -> Bool {
        safeAreaTop > 0 && leftAreaWidth > 0 && rightAreaWidth > 0
    }

    /// Finite, never negative, and never more than a quarter of the shorter side, so two corners and the
    /// edge between them always fit.
    public static func clampedRadius(_ radius: Double, in frame: CGRect) -> Double {
        guard radius.isFinite, radius > 0,
              frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0 else { return 0 }
        return min(radius, min(frame.width, frame.height) / 4)
    }

    /// The bottom-left and bottom-right squares of a screen frame (AppKit coordinates).
    public static func cornerFrames(screenFrame: CGRect, radius: Double) -> ScreenCornerFrames {
        let r = clampedRadius(radius, in: screenFrame)
        guard r > 0 else { return ScreenCornerFrames(radius: 0, bottomLeft: .zero, bottomRight: .zero) }
        return ScreenCornerFrames(
            radius: r,
            bottomLeft: CGRect(x: screenFrame.minX, y: screenFrame.minY, width: r, height: r),
            bottomRight: CGRect(x: screenFrame.maxX - r, y: screenFrame.minY, width: r, height: r))
    }

    /// The disc whose inside stays clear: its centre is the square's inner corner, opposite the screen corner.
    private static func discCentre(_ side: ScreenCornerSide, radius r: Double) -> CGPoint {
        switch side {
        case .bottomLeft: CGPoint(x: r, y: 0)
        case .bottomRight: CGPoint(x: 0, y: 0)
        }
    }

    /// Whether `point` (corner square coordinates, y down) is filled: inside the square and not inside the
    /// quarter disc. The arc itself counts as filled.
    public static func fills(_ point: CGPoint, side: ScreenCornerSide, radius r: Double) -> Bool {
        guard r.isFinite, r > 0, point.x.isFinite, point.y.isFinite,
              point.x >= 0, point.x <= r, point.y >= 0, point.y <= r else { return false }
        let centre = discCentre(side, radius: r)
        return hypot(point.x - centre.x, point.y - centre.y) >= r
    }

    /// The filled region as a closed outline (the last point joins the first), in corner square coordinates:
    /// the screen corner first, then the arc from one edge of the square to the other.
    public static func maskPoints(side: ScreenCornerSide, radius r: Double, segments: Int = 16) -> [CGPoint] {
        guard r.isFinite, r > 0 else { return [] }
        let steps = max(2, segments)
        let centre = discCentre(side, radius: r)
        let corner = CGPoint(x: side == .bottomLeft ? 0 : r, y: r)
        var points = [corner]
        // The arc runs from the far end of the square's outer side (angle pi for the left corner) to the
        // square's bottom (angle pi/2); the right corner is the mirror image.
        for step in 0...steps {
            let angle = Double.pi - (Double.pi / 2) * Double(step) / Double(steps)
            let x = r * cos(angle)
            points.append(CGPoint(x: side == .bottomLeft ? centre.x + x : centre.x - x, y: centre.y + r * sin(angle)))
        }
        return points
    }
}
