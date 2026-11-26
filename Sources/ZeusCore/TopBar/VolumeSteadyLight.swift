import Foundation

/// The volume mark that stays on the black top bar after the transient HUD has faded.
/// The bar itself does not change; this is only the light drawn on it.
public struct VolumeSteadyLight: Equatable, Sendable {
    public var level: Double
    public var muted: Bool

    public init(level: Double, muted: Bool) {
        let finite = level.isFinite ? level : 0
        self.level = min(1, max(0, finite))
        self.muted = muted
    }
}

public enum VolumeSteadyLightMath {
    /// A quiet or muted output still leaves a stub long enough to see on pitch black.
    public static let minimumVisibleFraction = 0.12
    /// Points. Thicker than the fading arm stroke so the mark reads on the black bar.
    public static let lineWidth = 3.0

    public struct Frame: Equatable, Sendable {
        public var fraction: Double
        public var opacity: Double
    }

    public static func visibleFraction(level: Double, muted: Bool) -> Double {
        let finite = level.isFinite ? min(1, max(0, level)) : 0
        if muted { return minimumVisibleFraction }
        return max(minimumVisibleFraction, finite)
    }

    /// Muted stays dim but still lit. Unmuted stays fully lit. Nothing here fades out.
    public static func opacity(muted: Bool) -> Double { muted ? 0.7 : 1 }

    /// `elapsed` does not retire the mark. The same inputs a minute later are the same light.
    public static func frame(level: Double, muted: Bool, elapsed: TimeInterval) -> Frame {
        _ = elapsed
        return Frame(fraction: visibleFraction(level: level, muted: muted), opacity: opacity(muted: muted))
    }

    /// Lit width along a span of points. Zero span stays zero; the mark never runs past the span.
    public static func litWidth(span: Double, level: Double, muted: Bool) -> Double {
        let span = span.isFinite ? max(0, span) : 0
        return span * visibleFraction(level: level, muted: muted)
    }

    public static func spoken(level: Double, muted: Bool) -> String {
        let finite = level.isFinite ? min(1, max(0, level)) : 0
        if muted || finite <= 0.001 { return "Volume muted" }
        return "Volume \(Int((finite * 100).rounded())) percent"
    }
}
