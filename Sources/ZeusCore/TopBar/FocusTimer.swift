import Foundation

/// A focus / break timer (pomodoro style) that is pure state, so the notch, the CLI and the
/// tests all read the same clock.
public struct FocusTimer: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case idle, focus, rest }

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
    private enum CodingKeys: String, CodingKey { case focusLength, restLength, phase, endsAt, pausedRemaining, completedRounds, roundsDay, timerRestores }

    public init(focusLength: TimeInterval = 25 * 60, restLength: TimeInterval = 5 * 60) {
        self.focusLength = focusLength
        self.restLength = restLength
    }

    public var isPaused: Bool { pausedRemaining != nil }
    public var isRunning: Bool { phase != .idle && !isPaused }

    public mutating func start(_ phase: Phase = .focus, at now: Date = Date()) {
        guard phase != .idle else { return stop() }
        self.phase = phase
        pausedRemaining = nil
        adjustment = 0
        endsAt = now.addingTimeInterval(phase == .focus ? focusLength : restLength)
    }

    /// Longest the timer will be set to, in minutes (the dial's last mark is `FocusDial.maxMinutes`; +5 can go further).
    public static let longestMinutes = 180

    /// "+5 min": idle, it lengthens the next round; running or paused, it pushes this one's end out.
    public mutating func extend(by seconds: TimeInterval = 5 * 60, at now: Date = Date()) {
        switch phase {
        case .idle:
            focusLength = min(focusLength + seconds, Double(Self.longestMinutes) * 60)
        default:
            let room = Double(Self.longestMinutes) * 60 - (remaining(at: now))
            let add = max(0, min(seconds, room))
            if let left = pausedRemaining { pausedRemaining = left + add } else { endsAt = endsAt?.addingTimeInterval(add) }
            adjustment += add
        }
    }

    /// Drag to set the time: idle it sets the round length; running or paused it sets what is left (and restarts the ring).
    public mutating func setTime(minutes: Int, at now: Date = Date()) {
        let seconds = Double(min(max(minutes, 1), Self.longestMinutes)) * 60
        switch phase {
        case .idle: focusLength = seconds
        default:
            if pausedRemaining != nil { pausedRemaining = seconds } else { endsAt = now.addingTimeInterval(seconds) }
            adjustment = seconds - (phase == .rest ? restLength : focusLength)
        }
    }

    /// The length the ring measures the current phase against.
    public var phaseLength: TimeInterval { (phase == .rest ? restLength : focusLength) + adjustment }

    public mutating func pause(at now: Date = Date()) {
        guard isRunning else { return }
        pausedRemaining = remaining(at: now)
        endsAt = nil
    }

    public mutating func resume(at now: Date = Date()) {
        guard let left = pausedRemaining else { return }
        pausedRemaining = nil
        endsAt = now.addingTimeInterval(left)
    }

    /// A one-off countdown on the same clock (voice "timer for N minutes"): no break afterwards,
    /// and the focus length goes back to what it was.
    public mutating func startTimer(seconds: TimeInterval, at now: Date = Date()) {
        if timerRestores == nil { timerRestores = focusLength }
        focusLength = seconds
        start(.focus, at: now)
    }

    public var isPlainTimer: Bool { timerRestores != nil }

    /// "2026-11-08" in the local calendar, so a round counts toward the day it finished on.
    public static func dayKey(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Rounds finished on the day of `now`; rounds counted on an earlier day (or before the day was kept) do not count.
    public func roundsToday(at now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        roundsDay == Self.dayKey(now, calendar: calendar) ? completedRounds : 0
    }

    public mutating func stop() {
        if let restore = timerRestores { focusLength = restore; timerRestores = nil }
        phase = .idle
        endsAt = nil
        pausedRemaining = nil
        adjustment = 0
    }

    public func remaining(at now: Date = Date()) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endsAt else { return 0 }
        return max(endsAt.timeIntervalSince(now), 0)
    }

    /// 0 at the start of a phase, 1 at the end.
    public func progress(at now: Date = Date()) -> Double {
        let total = phaseLength
        guard phase != .idle, total > 0 else { return 0 }
        return min(max(1 - remaining(at: now) / total, 0), 1)
    }

    /// Advances to the next phase when the current one has run out. Returns the phase that
    /// just finished, so the caller can announce it.
    public mutating func tick(at now: Date = Date()) -> Phase? {
        guard isRunning, remaining(at: now) <= 0 else { return nil }
        let finished = phase
        if finished == .focus, timerRestores != nil {
            stop()
        } else if finished == .focus {
            completedRounds = roundsToday(at: now) + 1
            roundsDay = Self.dayKey(now)
            start(.rest, at: now)
        } else {
            stop()
        }
        return finished
    }

    public static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The round dial on the Focus page: a drag around the ring sets the minutes (one turn is an hour, in 5 minute steps).
public enum FocusDial {
    public static let maxMinutes = 60
    public static let step = 5

    /// How far round the ring a point is: 0 at 12 o'clock, 0.25 at 3, growing clockwise. `dx` right and `dy` down from the centre.
    public static func fraction(dx: Double, dy: Double) -> Double {
        guard dx != 0 || dy != 0 else { return 0 }
        var turn = atan2(dx, -dy) / (2 * Double.pi)
        if turn < 0 { turn += 1 }
        return turn
    }

    /// Minutes for a ring position, snapped to `step`. The top of the ring is 5 coming from the right and 60 coming from the left
    /// (`previous` says which side the drag was on), so a drag can reach both ends.
    public static func minutes(fraction: Double, previous: Int = 0) -> Int {
        let f = min(max(fraction, 0), 1)
        let snapped = Int((f * Double(maxMinutes) / Double(step)).rounded()) * step
        if snapped <= 0 { return previous >= maxMinutes / 2 ? maxMinutes : step }
        return min(snapped, maxMinutes)
    }
}
