import Foundation

/// How far the closed top bar (notch body, light, ticker, wings, screen-edge glow and wave) sits below
/// the top of the screen. Pure math; the app owns the stored value and the windows.
///
/// Decision: one global choice (Settings > Appearance > Top bar position), not one per display.
/// A single slider is easier to reason about, and every notch-attached surface reads the same value.
/// While the owner has not moved the slider the default is automatic per display: a notched display
/// gets a small drop that clears the camera housing, a display without a notch gets none.
public enum TopBarPosition {
    public static let minimum = 0.0
    public static let maximum = 24.0
    public static let step = 2.0
    /// The automatic drop is this share of the notch height (the housing's rounded lower corners and
    /// the glow's bleed are what the camera covers).
    static let automaticShare = 0.3

    /// Finite, inside the range and on the step. NaN and infinity fall back to no offset.
    public static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return minimum }
        let snapped = (value / step).rounded() * step
        return min(max(snapped, minimum), maximum)
    }

    /// The default for a display: `notchHeight` is `NSScreen.safeAreaInsets.top` (0 without a notch).
    public static func automaticOffset(notchHeight: Double) -> Double {
        guard notchHeight.isFinite, notchHeight > 0 else { return minimum }
        return clamped(notchHeight * automaticShare)
    }

    /// What Settings stored (nil when the owner never moved the slider) or the automatic default.
    public static func resolved(chosen: Double?, notchHeight: Double) -> Double {
        if let chosen { return clamped(chosen) }
        return automaticOffset(notchHeight: notchHeight)
    }

    /// The open panel always sits flush with the top of the screen; only the closed bar and the
    /// peek card drop.
    public static func applied(resolved: Double, panelOpen: Bool) -> Double {
        panelOpen ? 0 : clamped(resolved)
    }
}
