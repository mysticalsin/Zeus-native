import Foundation

/// HUD wing expansion, opacity, and the open and close timing bars, as `Double` widths.
/// The caller supplies the spring remainder and the idle and final widths. This type does
/// not read a screen, a pointer, or a clock.
public enum SystemHUDWingMotionBox {
    public enum Kind: String, CaseIterable, Sendable {
        case volume, brightness, keyboard, mute, capsLock

        public var extraWidth: Double {
            switch self {
            case .volume, .brightness, .keyboard, .mute: 58
            case .capsLock: 30
            }
        }
    }

    public static let sampleFPS: Double = 120
    public static let frameStep: Double = 1.0 / 60.0
    public static let referenceNotchWidth: Double = 185
    public static let referenceBarHeight: Double = 32

    public struct Sample: Equatable, Sendable {
        public var time: Double
        public var width: Double
        public var height: Double
        public var opacity: Double

        public init(time: Double, width: Double, height: Double, opacity: Double) {
            self.time = time
            self.width = width
            self.height = height
            self.opacity = opacity
        }
    }

    /// Opening turns a remainder of 1 into idle and a remainder of 0 into the target.
    /// Both directions stay inside 0...1.06.
    public static func expansion(remaining: Double, opening: Bool) -> Double {
        let raw = opening ? 1 - remaining : remaining
        return max(0, min(1.06, raw))
    }

    public static func sample(
        time: Double,
        opening: Bool,
        expansion: Double,
        idle: Double,
        target: Double,
        height: Double = referenceBarHeight
    ) -> Sample {
        let delta = target - idle
        let width = idle + expansion * delta
        let opacity = opening ? min(1, expansion) : max(0, min(1, expansion))
        return Sample(time: time, width: width, height: height, opacity: opacity)
    }

    /// Samples from 0 through `seconds`, one step past the half-frame bound, at `sampleFPS`.
    /// `remaining` is read at each clamped time. A remainder of 1 holds an opening wing at idle.
    public static func timeline(
        seconds: Double = 0.35,
        opening: Bool,
        idle: Double,
        target: Double,
        height: Double = referenceBarHeight,
        remaining: (Double) -> Double
    ) -> [Sample] {
        let step = 1 / sampleFPS
        var out: [Sample] = []
        var t = 0.0
        while t <= seconds + step * 0.5 {
            let fraction = expansion(remaining: remaining(max(0, t)), opening: opening)
            out.append(sample(
                time: t, opening: opening, expansion: fraction, idle: idle, target: target, height: height))
            t += step
        }
        return out
    }

    /// PASS bar for an opening wing. Widths are plain numbers. `finalSize` is the settled width.
    public static func validateOpen(samples: [Sample], finalSize: Double) -> [String] {
        guard samples.count >= 2 else { return ["need samples"] }
        let idle = samples[0].width
        let delta = finalSize - idle
        guard delta > 1 else { return ["final size must exceed idle"] }

        var issues: [String] = []
        let first = samples[1]
        let firstExpansion = (first.width - idle) / delta
        if firstExpansion > 0.15 {
            issues.append("first frame expansion \(firstExpansion) > 0.15")
        }

        for index in 1..<samples.count {
            let prev = samples[index - 1]
            let cur = samples[index]
            if cur.time - prev.time > frameStep + 0.0001 { continue }
            let stepDelta = abs(cur.width - prev.width)
            if stepDelta > 0.25 * finalSize {
                issues.append("step at \(cur.time)s delta \(stepDelta) > 25% final")
            }
        }

        let hit95 = samples.first { sample in
            sample.time >= 0.08 && sample.time <= 0.15 && (sample.width - idle) / delta >= 0.95
        }
        if hit95 == nil {
            issues.append("did not reach 95% between 80 and 150 ms")
        }

        let peak = samples.map(\.width).max() ?? finalSize
        if peak > finalSize + 0.06 * delta {
            issues.append("overshoot \(peak - finalSize) > 6% of delta")
        }
        return issues
    }

    /// PASS bar for a closing wing. `idle` is the resting width the caller already measured.
    public static func validateClose(samples: [Sample], idle: Double, finalSize: Double) -> [String] {
        guard let start = samples.first else { return ["need samples"] }
        let delta = finalSize - idle
        guard delta > 1 else { return ["final size must exceed idle"] }

        var issues: [String] = []
        if abs(start.width - finalSize) > 0.5 {
            issues.append("close must start at final width")
        }

        let first = samples.count > 1 ? samples[1] : start
        let firstExpansion = (first.width - idle) / delta
        if firstExpansion < 0.85 {
            issues.append("first close frame shrank past 15% in one step")
        }

        for index in 1..<samples.count {
            let prev = samples[index - 1]
            let cur = samples[index]
            if cur.time - prev.time > frameStep + 0.0001 { continue }
            let stepDelta = abs(cur.width - prev.width)
            if stepDelta > 0.25 * finalSize {
                issues.append("close step at \(cur.time)s delta \(stepDelta) > 25% final")
            }
        }

        let nearZero = samples.first { sample in
            sample.time <= 0.15 && (sample.width - idle) / delta <= 0.05
        }
        if nearZero == nil {
            issues.append("did not reach 5% expansion within 150 ms on close")
        }

        if let last = samples.last, last.width <= idle + 0.5, last.opacity > 0.01 {
            issues.append("opacity jumped before width on close")
        }
        if let last = samples.last, last.width < idle - 1 {
            issues.append("width jumped below idle")
        }
        return issues
    }
}
