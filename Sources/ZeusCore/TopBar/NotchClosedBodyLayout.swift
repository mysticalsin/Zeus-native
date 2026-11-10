import CoreGraphics
import Foundation

/// Closed-notch body width while `.presentation == .closed` (wings, HUD cues, hardware notch).
/// Pure geometry so spring timing and width steps are unit tested without SwiftUI.
public enum NotchClosedBodyLayout {
    public static let wingWidth: CGFloat = 62
    public static let slimPillSize = CGSize(width: 96, height: 9)

    /// Spring for HUD cues widening the closed notch (R24: settle in under 120 ms).
    public static let wingsSpringResponse: Double = 0.09
    public static let wingsSpringDamping: Double = 0.86

    /// Extra width on the right wing for a cue kind (mirrors `ClosedWings.extraWidth` in the app target).
    public static func extraWingWidth(hasCue: Bool, cueExtra: CGFloat, wingKindExtra: CGFloat) -> CGFloat {
        guard hasCue else { return wingKindExtra }
        return cueExtra
    }

    /// The black body width at the top centre (ears included when `showWings`).
    public static func bodyWidth(
        notchWidth: CGFloat,
        shoulder: CGFloat,
        showWings: Bool,
        extraWidth: CGFloat,
        hasNotch: Bool,
        slimPill: Bool
    ) -> CGFloat {
        if showWings {
            let base = hasNotch ? notchWidth : 40
            return base + 2 * shoulder + 2 * wingWidth + extraWidth
        }
        if hasNotch { return notchWidth + 2 * shoulder }
        if slimPill { return slimPillSize.width }
        return 0
    }

    /// Whether a HUD volume/brightness cue should expand the closed body (lights or cue present).
    public static func showWings(closedWingKindIsNone: Bool, hasLights: Bool, hasLiveActivity: Bool) -> Bool {
        !closedWingKindIsNone || hasLights || hasLiveActivity
    }
}
