#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation

/// Focus and break timing, the round dial, and the countdown text.
/// The caller supplies the timer state, the current time, and the calendar.
/// This type does not read a screen, a pointer, a clock, or a stored setting.
public enum FocusTimerBox {
    public static let defaultFocusLength: TimeInterval = 25 * 60
    public static let defaultRestLength: TimeInterval = 5 * 60
    public static let longestMinutes = 180
    public static let defaultExtend: TimeInterval = 5 * 60

    public enum Phase: String, Codable, Equatable, Sendable {
        case idle, focus, rest
    }

    public struct State: Equatable, Sendable {
        public var focusLength: TimeInterval
        public var restLength: TimeInterval
        public var phase: Phase
        public var endsAt: Date?
        public var pausedRemaining: TimeInterval?
        public var completedRounds: Int
        public var roundsDay: String?
        public var timerRestores: TimeInterval?
        public var adjustment: TimeInterval

        public init(focusLength: TimeInterval = FocusTimerBox.defaultFocusLength,
                    restLength: TimeInterval = FocusTimerBox.defaultRestLength,
                    phase: Phase = .idle,
                    endsAt: Date? = nil,
                    pausedRemaining: TimeInterval? = nil,
                    completedRounds: Int = 0,
                    roundsDay: String? = nil,
                    timerRestores: TimeInterval? = nil,
                    adjustment: TimeInterval = 0) {
            self.focusLength = focusLength
            self.restLength = restLength
            self.phase = phase
            self.endsAt = endsAt
            self.pausedRemaining = pausedRemaining
            self.completedRounds = completedRounds
            self.roundsDay = roundsDay
            self.timerRestores = timerRestores
            self.adjustment = adjustment
        }
    }

    public static func isPaused(_ state: State) -> Bool { state.pausedRemaining != nil }

    public static func isRunning(_ state: State) -> Bool { state.phase != .idle && !isPaused(state) }

    public static func isPlainTimer(_ state: State) -> Bool { state.timerRestores != nil }

    public static func phaseLength(_ state: State) -> TimeInterval {
        (state.phase == .rest ? state.restLength : state.focusLength) + state.adjustment
    }

    public static func start(_ state: inout State, _ phase: Phase, at now: Date) {
        guard phase != .idle else { stop(&state); return }
        state.phase = phase
        state.pausedRemaining = nil
        state.adjustment = 0
        state.endsAt = now.addingTimeInterval(phase == .focus ? state.focusLength : state.restLength)
    }

    public static func extend(_ state: inout State, by seconds: TimeInterval, at now: Date) {
        switch state.phase {
        case .idle:
            state.focusLength = min(state.focusLength + seconds, Double(longestMinutes) * 60)
        default:
            let room = Double(longestMinutes) * 60 - remaining(state, at: now)
            let add = max(0, min(seconds, room))
            if let left = state.pausedRemaining {
                state.pausedRemaining = left + add
            } else {
                state.endsAt = state.endsAt?.addingTimeInterval(add)
            }
            state.adjustment += add
        }
    }

    public static func setTime(_ state: inout State, minutes: Int, at now: Date) {
        let seconds = Double(min(max(minutes, 1), longestMinutes)) * 60
        switch state.phase {
        case .idle:
            state.focusLength = seconds
        default:
            if state.pausedRemaining != nil {
                state.pausedRemaining = seconds
            } else {
                state.endsAt = now.addingTimeInterval(seconds)
            }
            state.adjustment = seconds - (state.phase == .rest ? state.restLength : state.focusLength)
        }
    }

    public static func pause(_ state: inout State, at now: Date) {
        guard isRunning(state) else { return }
        state.pausedRemaining = remaining(state, at: now)
        state.endsAt = nil
    }

    public static func resume(_ state: inout State, at now: Date) {
        guard let left = state.pausedRemaining else { return }
        state.pausedRemaining = nil
        state.endsAt = now.addingTimeInterval(left)
    }

    public static func startTimer(_ state: inout State, seconds: TimeInterval, at now: Date) {
        if state.timerRestores == nil { state.timerRestores = state.focusLength }
        state.focusLength = seconds
        start(&state, .focus, at: now)
    }

    public static func dayKey(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func roundsToday(_ state: State, at now: Date,
                                   calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        state.roundsDay == dayKey(now, calendar: calendar) ? state.completedRounds : 0
    }

    public static func stop(_ state: inout State) {
        if let restore = state.timerRestores {
            state.focusLength = restore
            state.timerRestores = nil
        }
        state.phase = .idle
        state.endsAt = nil
        state.pausedRemaining = nil
        state.adjustment = 0
    }

    public static func remaining(_ state: State, at now: Date) -> TimeInterval {
        if let pausedRemaining = state.pausedRemaining { return pausedRemaining }
        guard let endsAt = state.endsAt else { return 0 }
        return max(endsAt.timeIntervalSince(now), 0)
    }

    public static func progress(_ state: State, at now: Date) -> Double {
        let total = phaseLength(state)
        guard state.phase != .idle, total > 0 else { return 0 }
        return min(max(1 - remaining(state, at: now) / total, 0), 1)
    }

    public static func tick(_ state: inout State, at now: Date) -> Phase? {
        guard isRunning(state), remaining(state, at: now) <= 0 else { return nil }
        let finished = state.phase
        if finished == .focus, state.timerRestores != nil {
            stop(&state)
        } else if finished == .focus {
            state.completedRounds = roundsToday(state, at: now) + 1
            state.roundsDay = dayKey(now)
            start(&state, .rest, at: now)
        } else {
            stop(&state)
        }
        return finished
    }

    public static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// The round dial: a drag around the ring sets the minutes. One turn is an hour, in 5 minute steps.
    public enum Dial {
        public static let maxMinutes = 60
        public static let step = 5

        /// 0 at 12 o'clock, 0.25 at 3, growing clockwise. `dx` is right and `dy` is down from the centre.
        public static func fraction(dx: Double, dy: Double) -> Double {
            guard dx != 0 || dy != 0 else { return 0 }
            var turn = atan2(dx, -dy) / (2 * Double.pi)
            if turn < 0 { turn += 1 }
            return turn
        }

        /// Minutes for a ring position, snapped to `step`. The top is 5 from the right and 60 from the left.
        public static func minutes(fraction: Double, previous: Int = 0) -> Int {
            let clamped = min(max(fraction, 0), 1)
            let snapped = Int((clamped * Double(maxMinutes) / Double(step)).rounded()) * step
            if snapped <= 0 { return previous >= maxMinutes / 2 ? maxMinutes : step }
            return min(snapped, maxMinutes)
        }
    }
}
