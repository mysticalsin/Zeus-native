import Foundation

/// Opacity envelope and level spring for the screen-edge HUD glow.
/// This type does not read a screen, a pointer, a clock, or a stored setting.
public enum ScreenEdgeGlowBox {
    /// Springs in along the edge.
    public static let fadeIn = 0.12
    /// Shown fully lit after the last change, before the idle fade-out starts.
    public static let hold = 1.2
    /// Fades out once idle.
    public static let fadeOut = 0.25
    /// How quickly the drawn level tweens toward the new value.
    public static let levelSpring = 0.18

    public static var totalDuration: Double { fadeIn + hold + fadeOut }

    public struct Sample: Equatable, Sendable {
        public var level: Double
        public var opacity: Double
        public var isActive: Bool

        public init(level: Double, opacity: Double, isActive: Bool) {
            self.level = level
            self.opacity = opacity
            self.isActive = isActive
        }
    }

    /// `elapsed` is seconds since the change. A negative elapsed reads as the start.
    /// A level outside 0...1 is clamped. Reduce Motion shows the target level at once
    /// and keeps the same opacity envelope.
    public static func sample(fromLevel: Double, toLevel: Double, elapsed: Double, reduceMotion: Bool) -> Sample {
        let from = max(0, min(1, fromLevel))
        let to = max(0, min(1, toLevel))
        let t = max(0, elapsed)
        let opacity: Double
        if t < fadeIn {
            opacity = fadeIn > 0 ? t / fadeIn : 1
        } else if t < fadeIn + hold {
            opacity = 1
        } else if t < totalDuration {
            opacity = fadeOut > 0 ? 1 - (t - fadeIn - hold) / fadeOut : 0
        } else {
            opacity = 0
        }
        let level: Double
        if reduceMotion {
            level = to
        } else {
            let springProgress = easeOutCubic(levelSpring > 0 ? min(1, t / levelSpring) : 1)
            level = from + (to - from) * springProgress
        }
        return Sample(
            level: max(0, min(1, level)),
            opacity: max(0, min(1, opacity)),
            isActive: t < totalDuration
        )
    }

    /// The level a new change continues from while the previous light is still drawn.
    /// Once that light has finished, the fallback is returned unchanged.
    public static func startLevel(
        fromLevel: Double, toLevel: Double, elapsed: Double, reduceMotion: Bool, fallback: Double
    ) -> Double {
        let lit = sample(fromLevel: fromLevel, toLevel: toLevel, elapsed: elapsed, reduceMotion: reduceMotion)
        return lit.isActive ? lit.level : fallback
    }

    private static func easeOutCubic(_ x: Double) -> Double {
        let t = max(0, min(1, x))
        return 1 - pow(1 - t, 3)
    }
}
