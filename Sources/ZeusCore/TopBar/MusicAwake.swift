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
