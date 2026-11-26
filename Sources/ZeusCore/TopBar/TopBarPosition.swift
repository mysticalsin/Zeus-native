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
    public static let minimum = TopBarPositionBox.minimum
    public static let maximum = TopBarPositionBox.maximum
    public static let step = TopBarPositionBox.step

    /// Finite, inside the range and on the step. NaN and infinity fall back to no offset.
    public static func clamped(_ value: Double) -> Double {
        TopBarPositionBox.clamped(value)
    }

    /// What Settings stored, or no drop when the owner never moved the slider.
    public static func resolved(chosen: Double?) -> Double {
        TopBarPositionBox.resolved(chosen: chosen)
    }

    /// The open panel always sits flush with the top of the screen; only the closed bar and the
    /// peek card drop.
    public static func applied(resolved: Double, panelOpen: Bool) -> Double {
        TopBarPositionBox.applied(resolved: resolved, panelOpen: panelOpen)
    }
}

/// The right half of a screen's edge that the edge wave and the volume / brightness glow light: from the
/// top centre, round the top-right and bottom-right corners, to the bottom centre (the left half is its
/// mirror). In the overlay's own coordinates (origin top-left, y down), the size of the whole screen frame.
///
/// It always hugs the physical screen edge. The top bar's drop never moves it: a lowered top run left a
/// dark band above the light and floated the rounded corners off the real screen corners.
public struct ScreenEdgeOutline: Equatable, Sendable {
    public static let defaultInset = TopBarPositionBox.edgeInset
    public static let defaultRadius = TopBarPositionBox.edgeRadius

    public let centerX: Double
    public let top: Double
    public let right: Double
    public let bottom: Double
    /// The corner radius, never more than the half outline can hold.
    public let radius: Double

    public init(width: Double, height: Double, inset: Double = defaultInset, radius: Double = defaultRadius) {
        let outline = TopBarPositionBox.outline(width: width, height: height, inset: inset, radius: radius)
        centerX = outline.centerX
        top = outline.top
        right = outline.right
        bottom = outline.bottom
        self.radius = outline.radius
    }
}
