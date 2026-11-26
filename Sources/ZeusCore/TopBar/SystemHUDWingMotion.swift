import CoreGraphics
import Foundation

/// Headless model for Glance-style system HUD wing expansion (width, height, opacity).
/// Matches `NotchClosedBodyLayout` spring constants and `AnimatedNotchWidth` in the app.
/// Width, opacity, and the timing bars are read from `SystemHUDWingMotionBox`.
public enum SystemHUDWingMotion {
    public static let sampleFPS: Double = SystemHUDWingMotionBox.sampleFPS
    public static let frameStep: Double = SystemHUDWingMotionBox.frameStep

    /// Kinds exercised by `zeus debug animate` for HUD timing QA (silent, no hardware).
    public enum AnimateKind: String, CaseIterable, Sendable {
        case volume, brightness, keyboard, mute, capsLock

        public var cueExtraWidth: CGFloat {
            switch self {
            case .volume: CGFloat(SystemHUDWingMotionBox.Kind.volume.extraWidth)
            case .brightness: CGFloat(SystemHUDWingMotionBox.Kind.brightness.extraWidth)
            case .keyboard: CGFloat(SystemHUDWingMotionBox.Kind.keyboard.extraWidth)
            case .mute: CGFloat(SystemHUDWingMotionBox.Kind.mute.extraWidth)
            case .capsLock: CGFloat(SystemHUDWingMotionBox.Kind.capsLock.extraWidth)
            }
        }
    }

    public struct Sample: Equatable, Sendable {
        public var time: Double
        public var width: CGFloat
        public var height: CGFloat
        public var opacity: Double
    }

    public struct TimingIssue: Equatable, Sendable {
        public var message: String
    }

    public static let referenceNotchWidth: CGFloat = CGFloat(SystemHUDWingMotionBox.referenceNotchWidth)
    public static let referenceBarHeight: CGFloat = CGFloat(SystemHUDWingMotionBox.referenceBarHeight)

    public static func idleWidth(notchWidth: CGFloat = referenceNotchWidth, shoulder: CGFloat = 0) -> CGFloat {
        NotchClosedBodyLayout.bodyWidth(
            notchWidth: notchWidth, shoulder: shoulder, showWings: false,
            extraWidth: 0, hasNotch: true, slimPill: false)
    }

    public static func finalWidth(extraWidth: CGFloat, notchWidth: CGFloat = referenceNotchWidth, shoulder: CGFloat = 0) -> CGFloat {
        NotchClosedBodyLayout.bodyWidth(
            notchWidth: notchWidth, shoulder: shoulder, showWings: true,
            extraWidth: extraWidth, hasNotch: true, slimPill: false)
    }

    /// Fraction of wing expansion complete (0 idle, 1 at target). Opening uses 0→1 spring; closing 1→0.
    public static func expansion(at time: Double, opening: Bool) -> Double {
        let t = max(0, time)
        let remaining = GlanceTopBar.springRemaining(
            at: t,
            response: NotchClosedBodyLayout.wingsSpringResponse,
            damping: NotchClosedBodyLayout.wingsSpringDamping)
        return SystemHUDWingMotionBox.expansion(remaining: remaining, opening: opening)
    }

    public static func sample(at time: Double, opening: Bool, extraWidth: CGFloat,
                              notchWidth: CGFloat = referenceNotchWidth) -> Sample {
        let idle = Double(idleWidth(notchWidth: notchWidth))
        let target = Double(finalWidth(extraWidth: extraWidth, notchWidth: notchWidth))
        let placed = SystemHUDWingMotionBox.sample(
            time: time,
            opening: opening,
            expansion: expansion(at: time, opening: opening),
            idle: idle,
            target: target,
            height: Double(referenceBarHeight))
        return Sample(
            time: placed.time,
            width: CGFloat(placed.width),
            height: CGFloat(placed.height),
            opacity: placed.opacity)
    }

    public static func timeline(opening: Bool, extraWidth: CGFloat, seconds: Double = 0.35) -> [Sample] {
        let idle = Double(idleWidth())
        let target = Double(finalWidth(extraWidth: extraWidth))
        return SystemHUDWingMotionBox.timeline(
            seconds: seconds,
            opening: opening,
            idle: idle,
            target: target,
            height: Double(referenceBarHeight)
        ) { time in
            GlanceTopBar.springRemaining(
                at: time,
                response: NotchClosedBodyLayout.wingsSpringResponse,
                damping: NotchClosedBodyLayout.wingsSpringDamping)
        }.map { placed in
            Sample(
                time: placed.time,
                width: CGFloat(placed.width),
                height: CGFloat(placed.height),
                opacity: placed.opacity)
        }
    }

    /// PASS bar from R24 HUD smooth FIX (open).
    public static func validateOpen(_ samples: [Sample], finalSize: CGFloat) -> [TimingIssue] {
        SystemHUDWingMotionBox.validateOpen(samples: samples.map(boxSample), finalSize: Double(finalSize))
            .map { TimingIssue(message: $0) }
    }

    /// PASS bar for close (mirrors open).
    public static func validateClose(_ samples: [Sample], finalSize: CGFloat) -> [TimingIssue] {
        SystemHUDWingMotionBox.validateClose(
            samples: samples.map(boxSample),
            idle: Double(idleWidth()),
            finalSize: Double(finalSize)
        ).map { TimingIssue(message: $0) }
    }

    public static func validateKind(_ kind: AnimateKind) -> [TimingIssue] {
        let final = finalWidth(extraWidth: kind.cueExtraWidth)
        let open = timeline(opening: true, extraWidth: kind.cueExtraWidth)
        let close = timeline(opening: false, extraWidth: kind.cueExtraWidth)
        return validateOpen(open, finalSize: final) + validateClose(close, finalSize: final)
    }

    public static func allKindsPass() -> Bool {
        AnimateKind.allCases.allSatisfy { validateKind($0).isEmpty }
    }

    private static func boxSample(_ sample: Sample) -> SystemHUDWingMotionBox.Sample {
        .init(time: sample.time, width: Double(sample.width), height: Double(sample.height), opacity: sample.opacity)
    }
}
