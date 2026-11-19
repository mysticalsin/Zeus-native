import Foundation

/// How far the closed top bar (notch body, light, ticker and wings) sits below the top of the screen.
/// Pure math; the app owns the stored value and the windows.
///
/// Decisions:
/// - One global choice (Settings > Appearance > Top bar position), not one per display.
/// - No drop until the owner moves the slider. An automatic drop (30% of the notch height) used to apply
///   to every notched display; it detached the closed bar from the camera housing and made the bar slide
///   on every open and close, so the default is flush with the top again.
/// - The drop moves the closed notch capsule only. The screen-edge glow and edge wave always hug the
///   physical screen edge (`ScreenEdgeOutline` has no offset input).
public enum TopBarPosition {
    public static let minimum = 0.0
    public static let maximum = 24.0
    public static let step = 2.0

    /// Finite, inside the range and on the step. NaN and infinity fall back to no offset.
    public static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return minimum }
        let snapped = (value / step).rounded() * step
        return min(max(snapped, minimum), maximum)
    }

    /// What Settings stored, or no drop when the owner never moved the slider.
    public static func resolved(chosen: Double?) -> Double {
        chosen.map(clamped) ?? minimum
    }

    /// The open panel always sits flush with the top of the screen; only the closed bar and the
    /// peek card drop.
    public static func applied(resolved: Double, panelOpen: Bool) -> Double {
        panelOpen ? 0 : clamped(resolved)
    }
}

/// The right half of a screen's edge that the edge wave and the volume / brightness glow light: from the
/// top centre, round the top-right and bottom-right corners, to the bottom centre (the left half is its
/// mirror). In the overlay's own coordinates (origin top-left, y down), the size of the whole screen frame.
///
/// It always hugs the physical screen edge. The top bar's drop never moves it: a lowered top run left a
/// dark band above the light and floated the rounded corners off the real screen corners.
public struct ScreenEdgeOutline: Equatable, Sendable {
    public static let defaultInset = 2.0
    public static let defaultRadius = 12.0

    public let centerX: Double
    public let top: Double
    public let right: Double
    public let bottom: Double
    /// The corner radius, never more than the half outline can hold.
    public let radius: Double

    public init(width: Double, height: Double, inset: Double = defaultInset, radius: Double = defaultRadius) {
        let w = width.isFinite ? max(0, width) : 0
        let h = height.isFinite ? max(0, height) : 0
        let i = inset.isFinite ? max(0, inset) : 0
        centerX = w / 2
        top = i
        right = max(centerX, w - i)
        bottom = max(i, h - i)
        let room = min(right - centerX, (bottom - top) / 2)
        self.radius = max(0, min(radius.isFinite ? radius : 0, room))
    }
}
