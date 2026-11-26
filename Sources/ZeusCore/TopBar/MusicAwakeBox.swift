import Foundation

/// Grace, silence, and lease timing for holding the display on while music plays.
/// Off wins, then a pause outside the grace, then the power stop the caller already decided.
/// A pause inside the grace is not silence, so that stop still applies.
/// A gap counts as recent only when it is at least zero and strictly below the grace.
/// The caller supplies the clock reading and the last moment a track was seen playing.
/// This type does not read a screen, a pointer, a clock, or a stored setting.
public enum MusicAwakeBox {
    public enum Release: Equatable, Sendable {
        case off
        case notPlaying
        case lowBattery(Int)
        case tooHot
    }

    public enum Verdict: Equatable, Sendable {
        case hold
        case release(Release)

        public var holds: Bool { self == .hold }
    }

    /// The keep-awake stop, already decided. Clear means the session would keep going.
    /// This box does not rank heat against the battery.
    public enum PowerStop: Equatable, Sendable {
        case clear
        case lowBattery(Int)
        case tooHot
    }

    /// A pause or a gap between tracks shorter than this can keep the hold.
    public static let defaultGrace: TimeInterval = 20
    /// How long one assertion lasts if Zeus stops renewing it.
    public static let lease: TimeInterval = 120
    /// How often the lease is renewed while a hold is wanted.
    public static let renewEvery: TimeInterval = 60
    /// How late the system may fire the renewal timer, so it can batch wake-ups.
    public static let renewTolerance: TimeInterval = 10
    /// Room for the renewal work itself on top of a late timer.
    public static let margin: TimeInterval = 5

    /// Off wins. A pause that is not recent releases for silence, including over a power stop.
    /// A recent pause, and playback, use the power stop. Playing ignores the last play time.
    public static func decide(enabled: Bool, isPlaying: Bool, lastPlayedAt: Date?, now: Date,
                              grace: TimeInterval, power: PowerStop) -> Verdict {
        guard enabled else { return .release(.off) }
        if !isPlaying {
            let recent = lastPlayedAt.map { played in
                let gap = now.timeIntervalSince(played)
                return gap >= 0 && gap < grace
            } ?? false
            if !recent { return .release(.notPlaying) }
        }
        switch power {
        case .clear: return .hold
        case .lowBattery(let percent): return .release(.lowBattery(percent))
        case .tooHot: return .release(.tooHot)
        }
    }

    /// True when a renewal that fires a whole tolerance late, plus the margin, still comes before the lease
    /// ends, and the period is positive.
    public static func isSafe(lease: TimeInterval, renewEvery: TimeInterval, tolerance: TimeInterval,
                              margin: TimeInterval = margin) -> Bool {
        renewEvery > 0 && renewEvery + tolerance + margin < lease
    }
}
