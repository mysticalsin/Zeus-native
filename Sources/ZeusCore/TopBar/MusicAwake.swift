import Foundation

/// When Zeus holds the display on because music is playing. Pure, so the hold, the Settings copy
/// and the tests share one answer. The battery floor and heat rule are the keep-awake ones.
public struct MusicAwakeRule: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case off
        case notPlaying
        case lowBattery(Int)
        case tooHot
    }

    public enum Verdict: Equatable, Sendable {
        case hold
        case release(Reason)

        public var holds: Bool { self == .hold }
    }

    /// A pause or a gap between tracks shorter than this keeps the hold.
    public var grace: TimeInterval

    public init(grace: TimeInterval = 20) {
        self.grace = grace
    }

    /// `lastPlayedAt` is the last moment a track was seen playing. Off wins, then not playing, then
    /// heat, then battery. Charging or AC overrides the battery floor, as in `KeepAwakeRules`.
    public func decide(enabled: Bool, isPlaying: Bool, lastPlayedAt: Date?, now: Date,
                       power: KeepAwakeRules.Power, rules: KeepAwakeRules) -> Verdict {
        guard enabled else { return .release(.off) }
        if !isPlaying {
            // A play time in the future (clock set back) does not count as recent.
            guard let lastPlayedAt, case let gap = now.timeIntervalSince(lastPlayedAt), gap >= 0, gap < grace else {
                return .release(.notPlaying)
            }
        }
        switch rules.evaluate(power, elapsed: 0, remaining: nil, warned: true) {
        case .end(.lowBattery(let percent)): return .release(.lowBattery(percent))
        case .end(.tooHot): return .release(.tooHot)
        case .end(.timeUp), .keepGoing, .warnLowBattery: return .hold
        }
    }
}

/// The display hold's lease and how often it is renewed. A renewal that runs late must still land before
/// the lease ends, so the relation is a rule with a test, not a comment.
public enum MusicAwakeTiming {
    /// How long one assertion lasts if Zeus stops renewing it.
    public static let lease: TimeInterval = 120
    /// How often the lease is renewed while a hold is wanted.
    public static let renewEvery: TimeInterval = 60
    /// How late the system may fire the renewal timer, so it can batch wake-ups.
    public static let renewTolerance: TimeInterval = 10
    /// Room for the renewal work itself on top of a late timer.
    public static let margin: TimeInterval = 5

    /// True when a renewal that fires a whole tolerance late, plus the margin, still comes before the lease
    /// ends, and the period is positive.
    public static func isSafe(lease: TimeInterval, renewEvery: TimeInterval, tolerance: TimeInterval,
                              margin: TimeInterval = MusicAwakeTiming.margin) -> Bool {
        renewEvery > 0 && renewEvery + tolerance + margin < lease
    }
}
