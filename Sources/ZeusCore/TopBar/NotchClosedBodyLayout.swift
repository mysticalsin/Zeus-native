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
    /// How far the closed body of a hardware notch hangs below the notch's bottom edge, so the whole bottom outline
    /// and glow show instead of sitting under the hardware.
    public static let belowNotch: CGFloat = 6

    /// Spring for HUD cues widening the closed notch (R24: settle in under 120 ms); the numbers live in `MotionTokens`.
    public static let wingsSpringResponse: Double = MotionTokens.cueGrow.response
    public static let wingsSpringDamping: Double = MotionTokens.cueGrow.damping

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

    /// The frames `ClosedWingsRow` lays out. Music art or bars wider than the box are clipped to it, so one
    /// wing cannot grow by the 14 pt inset. Other wings stay the same width and may paint that inset outward.
    public struct ClosedWingRowLayout: Equatable, Sendable {
        public var gapWidth: CGFloat
        public var leftWidth: CGFloat
        public var rightWidth: CGFloat
        /// Extra paintable width outside the content box, outward only. Zero when the music content is clipped.
        public var outwardInset: CGFloat
        /// Width of the container that clips music. Zero when the wing is not clipped. A child `.clipped()` is not this.
        public var clipWidth: CGFloat

        public init(gapWidth: CGFloat, leftWidth: CGFloat, rightWidth: CGFloat, outwardInset: CGFloat, clipWidth: CGFloat) {
            self.gapWidth = gapWidth
            self.leftWidth = leftWidth
            self.rightWidth = rightWidth
            self.outwardInset = outwardInset
            self.clipWidth = clipWidth
        }
    }

    /// `leftProposal` and `rightProposal` are the widths the wing content would like. Music is clipped to the
    /// content box. Anything else may use the 14 pt inset, and both wings take that same width.
    public static func rowLayout(
        notchWidth: CGFloat,
        extra: CGFloat,
        leftProposal: CGFloat = 0,
        rightProposal: CGFloat = 0,
        clipsMusic: Bool
    ) -> ClosedWingRowLayout {
        let box = max(0, wingWidth - contentInset + extra)
        // Each wing keeps the width its content asked for. Art 14 pt wider than the bars makes the wings differ by 14.
        let left = max(box, leftProposal)
        let right = max(box, rightProposal)
        return ClosedWingRowLayout(gapWidth: notchWidth, leftWidth: left, rightWidth: right,
                                   outwardInset: clipsMusic ? 0 : contentInset,
                                   clipWidth: clipsMusic ? leftProposal : 0)
    }

    /// The widths the music wing actually offers: the bars fill the box, and the art is 14 pt wider at every scale.
    public static func musicContent(scale: CGFloat = 1) -> (art: CGFloat, bars: CGFloat) {
        let bars = max(0, wingWidth - contentInset) * scale
        return (bars + contentInset * scale, bars)
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

/// What the closed island is filled with (Settings > Appearance, id `notch.background`). Black is the default.
public enum NotchBackground: String, CaseIterable, Sendable {
    case black = "Black"
    case transparent = "Transparent"

    public static let settingID = "notch.background"

    /// The stored title, and Black for anything else.
    public static func resolve(_ title: String) -> NotchBackground { NotchBackground(rawValue: title) ?? .black }

    /// Which layers the body draws. Transparent drops all three while the notch is closed (the hardware notch is
    /// black by itself); the open panel and its cards keep theirs.
    public func layers(closed: Bool) -> NotchBodyLayers {
        let drawn = self == .black || !closed
        return NotchBodyLayers(fill: drawn, outline: drawn, glow: drawn)
    }
}

/// The layers of the notch body that may be drawn.
public struct NotchBodyLayers: Equatable, Sendable {
    public var fill: Bool
    public var outline: Bool
    public var glow: Bool

    public init(fill: Bool, outline: Bool, glow: Bool) {
        self.fill = fill
        self.outline = outline
        self.glow = glow
    }
}
