import CoreGraphics
import Foundation

/// Closed-notch body width while `.presentation == .closed` (wings, HUD cues, hardware notch).
/// Pure geometry so spring timing and width steps are unit tested without SwiftUI.
public enum NotchClosedBodyLayout {
    public static let wingWidth: CGFloat = 62
    /// Horizontal inset of the wing content inside the body padding (the body pads by shoulder + this).
    public static let contentInset: CGFloat = 14
    /// The gap a bar without a hardware notch keeps between its wings.
    public static let noNotchGap: CGFloat = 40
    /// The mini mascot beside the notch, and the extra the resting mascot (no word beside it) uses. Each wing is
    /// `wingWidth - contentInset + extra` wide, so the resting wing must stay at least as wide as the mascot.
    public static let miniMascotSize: CGFloat = 22
    public static let idleMascotExtra: CGFloat = -22
    public static let slimPillSize = CGSize(width: 96, height: 9)

    /// Spring for HUD cues widening the closed notch (R24: settle in under 120 ms).
    public static let wingsSpringResponse: Double = 0.09
    public static let wingsSpringDamping: Double = 0.86

    /// Where the closed wings sit, as x-ranges relative to the body centre. The body stays centred on the
    /// notch and both wings grow by the same extra, so the middle gap is exactly the notch.
    public struct WingGeometry: Equatable, Sendable {
        public var bodyWidth: CGFloat
        public var leftWing: ClosedRange<CGFloat>
        public var notchGap: ClosedRange<CGFloat>
        public var rightWing: ClosedRange<CGFloat>

        public var wingContentWidth: CGFloat { rightWing.upperBound - rightWing.lowerBound }
        public var gapWidth: CGFloat { notchGap.upperBound - notchGap.lowerBound }
    }

    /// `notchWidth` is the gap between the wings (the footprint's wing base).
    public static func closedWingGeometry(
        notchWidth: CGFloat,
        shoulder: CGFloat,
        wingWidth: CGFloat = NotchClosedBodyLayout.wingWidth,
        extra: CGFloat,
        inset: CGFloat = contentInset
    ) -> WingGeometry {
        let half = notchWidth / 2
        let content = max(0, wingWidth - inset + extra)
        return WingGeometry(
            bodyWidth: notchWidth + 2 * shoulder + 2 * (wingWidth + extra),
            leftWing: -half - content ... -half,
            notchGap: -half ... half,
            rightWing: half ... half + content)
    }

    /// Extra width on each wing for a cue kind (mirrors `ClosedWings.extraWidth` in the app target).
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
            let base = hasNotch ? notchWidth : noNotchGap
            return closedWingGeometry(notchWidth: base, shoulder: shoulder, extra: extraWidth).bodyWidth
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
