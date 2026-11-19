import Foundation

/// The opening choreography of the Scribe page, as plain numbers. One table decides every delay, duration and
/// offset, so the view code holds no timing of its own and the tests pin it.
///
/// Order: the panel eases in, the capture button settles (with one light sweep), the "Up next" card and the chips
/// follow 40 ms apart, the breathing wave fades up last, and on the Memory window the mascot strip peeks in.
/// Closing plays the same pieces with no delay and shorter durations. Reduce Motion: one plain crossfade.
public enum ScribeOpenSequence {
    public enum Stage: CaseIterable, Sendable {
        case panel, capture, upNext, chips, wave, mascot
    }

    public static let stagger: TimeInterval = 0.04
    /// The panel's spring settles in about this long.
    public static let panelDuration: TimeInterval = 0.35
    /// Closing is this much faster than opening.
    public static let closeSpeedup = 0.6
    public static let reducedMotionFade: TimeInterval = 0.12
    public static let sweepDuration: TimeInterval = 0.5

    public static func delay(_ stage: Stage, closing: Bool = false) -> TimeInterval {
        if closing { return 0 }
        switch stage {
        case .panel: return 0
        case .capture: return 0.08
        case .upNext: return 0.08 + stagger
        case .chips: return 0.08 + 2 * stagger
        case .wave: return 0.08 + 2 * stagger + 0.10
        case .mascot: return 0.20
        }
    }

    public static func duration(_ stage: Stage, closing: Bool = false) -> TimeInterval {
        let base: TimeInterval = stage == .panel ? panelDuration : (stage == .wave ? 0.4 : 0.3)
        return closing ? base * closeSpeedup : base
    }

    /// Where a piece starts (opening) or ends (closing): scale of the panel, vertical drop in points of the others.
    public static func startScale(_ stage: Stage) -> Double { stage == .panel ? 0.97 : 1 }

    public static func startOffset(_ stage: Stage) -> Double {
        switch stage {
        case .panel: return -8
        case .capture, .upNext, .chips: return 8
        case .wave: return 0
        case .mascot: return 40
        }
    }

    /// Everything is finished this long after opening starts, so nothing is left running.
    public static var totalDuration: TimeInterval {
        Stage.allCases.map { delay($0) + duration($0) }.max() ?? 0
    }
}
