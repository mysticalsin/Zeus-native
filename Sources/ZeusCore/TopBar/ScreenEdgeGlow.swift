import Foundation

/// P0 item G: the screen-edge HUD glow. On a volume, brightness or keyboard-backlight change (and
/// mute), a click-through overlay above the menu bar on every display draws an edge stroke that
/// fills in with the level, joining the notch at the top centre. Pure math and timing live here
/// (no AppKit) so they are unit-testable; `ScreenEdgeGlowController` (Sources/Zeus/Notch) owns the
/// actual panels and drives this from `TopBarModel.presentSystemHUD`.
///
/// Event-driven only, never a free-running clock (plan NEXT note for G/I): a caller re-presents on
/// every real HUD change, and `frame(...).isActive` tells the caller when it can stop ticking and
/// hide, instead of a timer that runs forever.
public struct ScreenEdgeGlowState: Equatable, Sendable {
    public var kind: SystemHUDKind
    public var fromLevel: Double
    public var toLevel: Double
    public var muted: Bool
    public var changedAt: Date

    public init(kind: SystemHUDKind, fromLevel: Double, toLevel: Double, muted: Bool, changedAt: Date) {
        self.kind = kind
        self.fromLevel = max(0, min(1, fromLevel))
        self.toLevel = max(0, min(1, toLevel))
        self.muted = muted
        self.changedAt = changedAt
    }
}

public struct ScreenEdgeGlowFrame: Equatable, Sendable {
    public var level: Double
    public var opacity: Double
    /// True while anything should still be drawn (and the caller's ticking view should keep
    /// running); false once the fade-out has fully finished.
    public var isActive: Bool
}

public enum ScreenEdgeGlowMath {
    /// Springs in along the edge.
    public static let fadeIn: TimeInterval = 0.12
    /// Shown fully lit after the last change, before the idle fade-out starts.
    public static let hold: TimeInterval = 1.2
    /// Fades out once idle.
    public static let fadeOut: TimeInterval = 0.25
    /// How quickly the drawn level itself tweens toward the new value, independent of the
    /// opacity envelope above (same spring feel as the notch's own H2/H3 arm).
    public static let levelSpring: TimeInterval = 0.18

    public static var totalDuration: TimeInterval { fadeIn + hold + fadeOut }

    static func easeOutCubic(_ x: Double) -> Double {
        let t = max(0, min(1, x))
        return 1 - pow(1 - t, 3)
    }

    /// Deterministic, pure: same inputs always give the same frame. `now` may be before
    /// `state.changedAt` (clock skew) -- treated as elapsed 0, never negative.
    public static func frame(_ state: ScreenEdgeGlowState, now: Date, reduceMotion: Bool) -> ScreenEdgeGlowFrame {
        let elapsed = max(0, now.timeIntervalSince(state.changedAt))
        let opacity: Double
        if elapsed < fadeIn {
            opacity = fadeIn > 0 ? elapsed / fadeIn : 1
        } else if elapsed < fadeIn + hold {
            opacity = 1
        } else if elapsed < totalDuration {
            opacity = fadeOut > 0 ? 1 - (elapsed - fadeIn - hold) / fadeOut : 0
        } else {
            opacity = 0
        }
        let level: Double
        if reduceMotion {
            // No travelling spring under Reduce Motion: a plain fade at the target level.
            level = state.toLevel
        } else {
            let springProgress = easeOutCubic(levelSpring > 0 ? min(1, elapsed / levelSpring) : 1)
            level = state.fromLevel + (state.toLevel - state.fromLevel) * springProgress
        }
        return ScreenEdgeGlowFrame(level: max(0, min(1, level)), opacity: max(0, min(1, opacity)), isActive: elapsed < totalDuration)
    }

    /// Where a *new* change should spring from: the level already on screen if the previous
    /// state is still active (continues the same light, matching H2's "no restart" rule),
    /// otherwise the plain target value (nothing was lit, so there is nothing to continue from).
    public static func startLevel(previous: ScreenEdgeGlowState?, now: Date, reduceMotion: Bool, fallback: Double) -> Double {
        guard let previous else { return fallback }
        let previousFrame = frame(previous, now: now, reduceMotion: reduceMotion)
        return previousFrame.isActive ? previousFrame.level : fallback
    }
}
