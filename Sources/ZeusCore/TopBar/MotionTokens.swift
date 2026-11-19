import Foundation

/// A SwiftUI spring as two numbers: `response` in seconds and `damping` as a fraction (1 is critically damped).
public struct SpringToken: Equatable, Sendable {
    public var response: Double
    public var damping: Double

    public init(response: Double, damping: Double) {
        self.response = response
        self.damping = damping
    }
}

/// The one table of motion tokens (docs/SMOOTH-MOTION-PLAN.md, section 2). Views read these, never literals.
public enum MotionTokens {
    /// Panel width on hover open.
    public static let panelOpen = SpringToken(response: 0.30, damping: 0.87)
    /// Panel height on hover open; it leads the width.
    public static let panelOpenHeight = SpringToken(response: 0.105, damping: 1.0)
    /// Panel close: critically damped, no overshoot, fitted to the recorded close heights.
    public static let panelClose = SpringToken(response: 0.175, damping: 1.0)
    /// Panel resize on a tab change, and page content.
    public static let panelResize = SpringToken(response: 0.34, damping: 0.84)
    /// HUD cue wings growing: settles in about 105 ms over 120 pt.
    public static let cueGrow = SpringToken(response: 0.12, damping: 0.90)
    /// Content that peeks in beside the closed notch.
    public static let peekContent = SpringToken(response: 0.34, damping: 0.82)
    public static let peekContentDelay = 0.1

    /// A page leaving fades out this fast (seconds, ease out).
    public static let pageOutDuration = 0.08
    public static let crossfadeDuration = 0.12
    public static let pressDuration = 0.12
    public static let pressScale = 0.98
    /// Window fades, with explicit AppKit timing.
    public static let windowFadeInDuration = 0.2
    public static let windowFadeOutDuration = 0.25

    public static let allSprings: [SpringToken] = [panelOpen, panelOpenHeight, panelClose, panelResize, cueGrow, peekContent]
}

/// Frame-rate rules for animation that is driven by a clock rather than a SwiftUI animation.
public enum MotionRules {
    /// The fastest display Zeus targets (ProMotion).
    public static let displayMaxFPS = 120
    /// Ambient loops (halo, level bars, orbs) run at a divisor of the display rate.
    public static let ambientFPS = 60
    /// A spinner turns at the display rate so its steps are never visible.
    public static let spinnerFPS = 120
    /// Travel windows of the mascot (a stroll across the notch).
    public static let travelFPS = 60.0

    /// How fast the mascot's frame clock runs: the clip's own rate, or 60 while it travels.
    public static func fps(clipFPS: Double, travelling: Bool) -> Double {
        travelling ? travelFPS : clipFPS
    }
}
