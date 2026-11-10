import CoreGraphics
import Foundation

/// Headless model for Glance-style system HUD wing expansion (width, height, opacity).
/// Matches `NotchClosedBodyLayout` spring constants and `AnimatedNotchWidth` in the app.
public enum SystemHUDWingMotion {
    public static let sampleFPS: Double = 120
    public static let frameStep: Double = 1.0 / 60.0

    /// Kinds exercised by `zeus debug animate` for HUD timing QA (silent, no hardware).
    public enum AnimateKind: String, CaseIterable, Sendable {
        case volume, brightness, keyboard, mute, capsLock

        public var cueExtraWidth: CGFloat {
            switch self {
            case .volume, .brightness, .keyboard, .mute: 58
            case .capsLock: 30
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

    public static let referenceNotchWidth: CGFloat = 185
    public static let referenceBarHeight: CGFloat = 32

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
        let raw = opening ? 1 - remaining : remaining
        return max(0, min(1.06, raw))
    }

    public static func sample(at time: Double, opening: Bool, extraWidth: CGFloat,
                              notchWidth: CGFloat = referenceNotchWidth) -> Sample {
        let idle = idleWidth(notchWidth: notchWidth)
        let target = finalWidth(extraWidth: extraWidth, notchWidth: notchWidth)
        let delta = target - idle
        let e = expansion(at: time, opening: opening)
        let width = idle + CGFloat(e) * delta
        let opacity = opening ? min(1, e) : max(0, min(1, e))
        return Sample(time: time, width: width, height: referenceBarHeight, opacity: opacity)
    }

    public static func timeline(opening: Bool, extraWidth: CGFloat, seconds: Double = 0.35) -> [Sample] {
        let step = 1 / sampleFPS
        var out: [Sample] = []
        var t = 0.0
        while t <= seconds + step * 0.5 {
            out.append(sample(at: t, opening: opening, extraWidth: extraWidth))
            t += step
        }
        return out
    }

    /// PASS bar from R24 HUD smooth FIX (open).
    public static func validateOpen(_ samples: [Sample], finalSize: CGFloat) -> [TimingIssue] {
        guard samples.count >= 2 else { return [TimingIssue(message: "need samples")] }
        let idle = samples[0].width
        let delta = finalSize - idle
        guard delta > 1 else { return [TimingIssue(message: "final size must exceed idle")] }

        var issues: [TimingIssue] = []
        let first = samples[1]
        let firstExpansion = (first.width - idle) / delta
        if firstExpansion > 0.15 {
            issues.append(TimingIssue(message: "first frame expansion \(firstExpansion) > 0.15"))
        }

        for index in 1..<samples.count {
            let prev = samples[index - 1]
            let cur = samples[index]
            if cur.time - prev.time > frameStep + 0.0001 { continue }
            let stepDelta = abs(cur.width - prev.width)
            if stepDelta > 0.25 * finalSize {
                issues.append(TimingIssue(message: "step at \(cur.time)s delta \(stepDelta) > 25% final"))
            }
        }

        let hit95 = samples.first { s in
            s.time >= 0.08 && s.time <= 0.15 && (s.width - idle) / delta >= 0.95
        }
        if hit95 == nil {
            issues.append(TimingIssue(message: "did not reach 95% between 80 and 150 ms"))
        }

        let peak = samples.map(\.width).max() ?? finalSize
        if peak > finalSize + 0.06 * delta {
            issues.append(TimingIssue(message: "overshoot \(peak - finalSize) > 6% of delta"))
        }
        return issues
    }

    /// PASS bar for close (mirrors open).
    public static func validateClose(_ samples: [Sample], finalSize: CGFloat) -> [TimingIssue] {
        guard let start = samples.first else { return [TimingIssue(message: "need samples")] }
        let idle = SystemHUDWingMotion.idleWidth()
        let delta = finalSize - idle
        guard delta > 1 else { return [TimingIssue(message: "final size must exceed idle")] }

        var issues: [TimingIssue] = []
        if abs(start.width - finalSize) > 0.5 {
            issues.append(TimingIssue(message: "close must start at final width"))
        }

        let first = samples.count > 1 ? samples[1] : start
        let firstExpansion = (first.width - idle) / delta
        if firstExpansion < 0.85 {
            issues.append(TimingIssue(message: "first close frame shrank past 15% in one step"))
        }

        for index in 1..<samples.count {
            let prev = samples[index - 1]
            let cur = samples[index]
            if cur.time - prev.time > frameStep + 0.0001 { continue }
            let stepDelta = abs(cur.width - prev.width)
            if stepDelta > 0.25 * finalSize {
                issues.append(TimingIssue(message: "close step at \(cur.time)s delta \(stepDelta) > 25% final"))
            }
        }

        let nearZero = samples.first { s in
            s.time <= 0.15 && (s.width - idle) / delta <= 0.05
        }
        if nearZero == nil {
            issues.append(TimingIssue(message: "did not reach 5% expansion within 150 ms on close"))
        }

        if let last = samples.last, last.width <= idle + 0.5, last.opacity > 0.01 {
            issues.append(TimingIssue(message: "opacity jumped before width on close"))
        }
        if let last = samples.last, last.width < idle - 1 {
            issues.append(TimingIssue(message: "width jumped below idle"))
        }
        return issues
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
}
