import Foundation

/// A focus / break timer (pomodoro style) that is pure state, so the notch, the CLI and the
/// tests all read the same clock.
public struct FocusTimer: Codable, Equatable, Sendable {
    public typealias Phase = FocusTimerBox.Phase

    public var focusLength: TimeInterval
    public var restLength: TimeInterval
    public private(set) var phase: Phase = .idle
    public private(set) var endsAt: Date?
    /// Remaining time while paused.
    public private(set) var pausedRemaining: TimeInterval?
    public private(set) var completedRounds = 0
    /// The calendar day (yyyy-MM-dd) `completedRounds` was counted on; nil for rounds saved before the day was kept.
    public private(set) var roundsDay: String?
    /// Set while a plain timer ("set a timer for 5 minutes") runs: the focus length to restore after.
    /// A plain timer ends without a break.
    public private(set) var timerRestores: TimeInterval?
    /// Seconds added to (or set over) the current phase with "+5 min" or the dial; cleared when a phase starts or stops.
    public private(set) var adjustment: TimeInterval = 0

    // `adjustment` is per run, never saved.
    private enum CodingKeys: String, CodingKey {
        case focusLength, restLength, phase, endsAt, pausedRemaining, completedRounds, roundsDay, timerRestores
    }

    public init(focusLength: TimeInterval = FocusTimerBox.defaultFocusLength,
                restLength: TimeInterval = FocusTimerBox.defaultRestLength) {
        self.focusLength = focusLength
        self.restLength = restLength
    }

    public var isPaused: Bool { FocusTimerBox.isPaused(rules) }
    public var isRunning: Bool { FocusTimerBox.isRunning(rules) }

    private var rules: FocusTimerBox.State {
        get {
            FocusTimerBox.State(focusLength: focusLength, restLength: restLength, phase: phase,
                                 endsAt: endsAt, pausedRemaining: pausedRemaining,
                                 completedRounds: completedRounds, roundsDay: roundsDay,
                                 timerRestores: timerRestores, adjustment: adjustment)
        }
        set {
            focusLength = newValue.focusLength
            restLength = newValue.restLength
            phase = newValue.phase
            endsAt = newValue.endsAt
            pausedRemaining = newValue.pausedRemaining
            completedRounds = newValue.completedRounds
            roundsDay = newValue.roundsDay
            timerRestores = newValue.timerRestores
            adjustment = newValue.adjustment
        }
    }

    public mutating func start(_ phase: Phase = .focus, at now: Date = Date()) {
        var state = rules
        FocusTimerBox.start(&state, phase, at: now)
        rules = state
    }

    /// Longest the timer will be set to, in minutes (the dial's last mark is `FocusDial.maxMinutes`; +5 can go further).
    public static let longestMinutes = FocusTimerBox.longestMinutes

    /// "+5 min": idle, it lengthens the next round; running or paused, it pushes this one's end out.
    public mutating func extend(by seconds: TimeInterval = FocusTimerBox.defaultExtend, at now: Date = Date()) {
        var state = rules
        FocusTimerBox.extend(&state, by: seconds, at: now)
        rules = state
    }

    /// Drag to set the time: idle it sets the round length; running or paused it sets what is left (and restarts the ring).
    public mutating func setTime(minutes: Int, at now: Date = Date()) {
        var state = rules
        FocusTimerBox.setTime(&state, minutes: minutes, at: now)
        rules = state
    }

    /// The length the ring measures the current phase against.
    public var phaseLength: TimeInterval { FocusTimerBox.phaseLength(rules) }

    public mutating func pause(at now: Date = Date()) {
        var state = rules
        FocusTimerBox.pause(&state, at: now)
        rules = state
    }

    public mutating func resume(at now: Date = Date()) {
        var state = rules
        FocusTimerBox.resume(&state, at: now)
        rules = state
    }

    /// A one-off countdown on the same clock (voice "timer for N minutes"): no break afterwards,
    /// and the focus length goes back to what it was.
    public mutating func startTimer(seconds: TimeInterval, at now: Date = Date()) {
        var state = rules
        FocusTimerBox.startTimer(&state, seconds: seconds, at: now)
        rules = state
    }

    public var isPlainTimer: Bool { FocusTimerBox.isPlainTimer(rules) }

    /// "2026-11-08" in the local calendar, so a round counts toward the day it finished on.
    public static func dayKey(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        FocusTimerBox.dayKey(date, calendar: calendar)
    }

    /// Rounds finished on the day of `now`; rounds counted on an earlier day (or before the day was kept) do not count.
    public func roundsToday(at now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        FocusTimerBox.roundsToday(rules, at: now, calendar: calendar)
    }

    public mutating func stop() {
        var state = rules
        FocusTimerBox.stop(&state)
        rules = state
    }

    public func remaining(at now: Date = Date()) -> TimeInterval {
        FocusTimerBox.remaining(rules, at: now)
    }

    /// 0 at the start of a phase, 1 at the end.
    public func progress(at now: Date = Date()) -> Double {
        FocusTimerBox.progress(rules, at: now)
    }

    /// Advances to the next phase when the current one has run out. Returns the phase that
    /// just finished, so the caller can announce it.
    public mutating func tick(at now: Date = Date()) -> Phase? {
        var state = rules
        let finished = FocusTimerBox.tick(&state, at: now)
        rules = state
        return finished
    }

    public static func format(_ seconds: TimeInterval) -> String {
        FocusTimerBox.format(seconds)
    }
}

/// The round dial on the Focus page: a drag around the ring sets the minutes (one turn is an hour, in 5 minute steps).
public enum FocusDial {
    public static let maxMinutes = FocusTimerBox.Dial.maxMinutes
    public static let step = FocusTimerBox.Dial.step

    /// How far round the ring a point is: 0 at 12 o'clock, 0.25 at 3, growing clockwise. `dx` right and `dy` down from the centre.
    public static func fraction(dx: Double, dy: Double) -> Double {
        FocusTimerBox.Dial.fraction(dx: dx, dy: dy)
    }

    /// Minutes for a ring position, snapped to `step`. The top of the ring is 5 coming from the right and 60 coming from the left
    /// (`previous` says which side the drag was on), so a drag can reach both ends.
    public static func minutes(fraction: Double, previous: Int = 0) -> Int {
        FocusTimerBox.Dial.minutes(fraction: fraction, previous: previous)
    }
}
