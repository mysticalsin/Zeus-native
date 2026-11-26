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
        self.fromLevel = ScreenEdgeGlowBox.clampedLevel(fromLevel)
        self.toLevel = ScreenEdgeGlowBox.clampedLevel(toLevel)
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
    public static let fadeIn: TimeInterval = ScreenEdgeGlowBox.fadeIn
    /// Shown fully lit after the last change, before the idle fade-out starts.
    public static let hold: TimeInterval = ScreenEdgeGlowBox.hold
    /// Fades out once idle.
    public static let fadeOut: TimeInterval = ScreenEdgeGlowBox.fadeOut
    /// How quickly the drawn level itself tweens toward the new value, independent of the
    /// opacity envelope above (same spring feel as the notch's own H2/H3 arm).
    public static let levelSpring: TimeInterval = ScreenEdgeGlowBox.levelSpring

    public static var totalDuration: TimeInterval { ScreenEdgeGlowBox.totalDuration }

    /// Deterministic, pure: same inputs always give the same frame. `now` may be before
    /// `state.changedAt` (clock skew) -- treated as elapsed 0, never negative.
    public static func frame(_ state: ScreenEdgeGlowState, now: Date, reduceMotion: Bool) -> ScreenEdgeGlowFrame {
        let drawn = ScreenEdgeGlowBox.frame(
            elapsed: now.timeIntervalSince(state.changedAt),
            fromLevel: state.fromLevel,
            toLevel: state.toLevel,
            reduceMotion: reduceMotion
        )
        return ScreenEdgeGlowFrame(level: drawn.level, opacity: drawn.opacity, isActive: drawn.isActive)
    }

    /// Where a *new* change should spring from: the level already on screen if the previous
    /// state is still active (continues the same light, matching H2's "no restart" rule),
    /// otherwise the plain target value (nothing was lit, so there is nothing to continue from).
    public static func startLevel(previous: ScreenEdgeGlowState?, now: Date, reduceMotion: Bool, fallback: Double) -> Double {
        guard let previous else { return fallback }
        return ScreenEdgeGlowBox.continuedLevel(
            previousElapsed: now.timeIntervalSince(previous.changedAt),
            previousFrom: previous.fromLevel,
            previousTo: previous.toLevel,
            reduceMotion: reduceMotion,
            fallback: fallback
        )
    }
}
