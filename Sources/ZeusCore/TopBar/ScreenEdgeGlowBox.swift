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

    public struct Frame: Equatable, Sendable {
        public var level: Double
        public var opacity: Double
        public var isActive: Bool

        public init(level: Double, opacity: Double, isActive: Bool) {
            self.level = level
            self.opacity = opacity
            self.isActive = isActive
        }
    }

    /// The same 0...1 clamp the glow state already stores. A value that is not finite follows that clamp.
    public static func clampedLevel(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    public static func easeOutCubic(_ x: Double) -> Double {
        let t = max(0, min(1, x))
        return 1 - pow(1 - t, 3)
    }

    /// Deterministic: the same inputs always give the same frame. Elapsed below zero, or not finite,
    /// reads as the start. A finished glow is dark. The level is the target once the spring is done.
    public static func frame(elapsed: Double, fromLevel: Double, toLevel: Double, reduceMotion: Bool) -> Frame {
        let t = max(0, elapsed)
        let from = clampedLevel(fromLevel)
        let to = clampedLevel(toLevel)
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
        return Frame(
            level: max(0, min(1, level)),
            opacity: max(0, min(1, opacity)),
            isActive: t < totalDuration
        )
    }

    /// The level a new change springs from. No previous glow uses the fallback. An active glow
    /// continues its current level. A glow that has finished uses the fallback unchanged.
    public static func continuedLevel(
        previousElapsed: Double?, previousFrom: Double, previousTo: Double, reduceMotion: Bool, fallback: Double
    ) -> Double {
        guard let previousElapsed else { return fallback }
        let drawn = frame(
            elapsed: previousElapsed, fromLevel: previousFrom, toLevel: previousTo, reduceMotion: reduceMotion
        )
        return drawn.isActive ? drawn.level : fallback
    }
}
