import Foundation

/// The 3, 2, 1 between pressing Record and the capture starting.
/// The caller supplies the countdown and each event. A tick carries the token it was given.
/// This type does not read a screen, a pointer, a clock, or a stored setting.
public enum RecordlyCountdownBox {
    public static let seconds = 3

    public enum State: Equatable, Sendable {
        case idle
        case counting(remaining: Int, token: UInt64)
    }

    public enum Event: Equatable, Sendable {
        /// The Record button. A second press while counting cancels.
        case press(sourceReady: Bool)
        /// `sourceReady` is whether the chosen display or window still exists; a countdown never ends in a silent no-op.
        case tick(token: UInt64, sourceReady: Bool = true)
        /// Escape, or the page going away.
        case cancel
        /// The selected display or window went away while counting.
        case sourceUnavailable(reason: String)
    }

    public enum Effect: Equatable, Sendable {
        case scheduleTick(token: UInt64)
        case cancelTick
        case startCapture
        case notice(String)
    }

    public struct Machine: Equatable, Sendable {
        public var state: State
        public var nextToken: UInt64

        public init(state: State = .idle, nextToken: UInt64 = 0) {
            self.state = state
            self.nextToken = nextToken
        }

        public var isCounting: Bool { if case .counting = state { true } else { false } }

        public var remaining: Int? {
            if case .counting(let remaining, _) = state { remaining } else { nil }
        }
    }

    public static let noSourceNotice = "Choose a display or window first."
    public static let sourceLostNotice = "The source went away before recording started. Choose it again."

    public static func send(_ machine: inout Machine, _ event: Event) -> [Effect] {
        switch (machine.state, event) {
        case (.idle, .press(let ready)):
            guard ready else { return [.notice(noSourceNotice)] }
            machine.nextToken &+= 1
            machine.state = .counting(remaining: seconds, token: machine.nextToken)
            return [.scheduleTick(token: machine.nextToken)]

        case (.counting, .press), (.counting, .cancel):
            machine.state = .idle
            return [.cancelTick]

        case (.counting(let remaining, let token), .tick(let tickToken, let sourceReady)):
            guard tickToken == token else { return [] }
            guard sourceReady else {
                machine.state = .idle
                return [.cancelTick, .notice(sourceLostNotice)]
            }
            if remaining > 1 {
                machine.state = .counting(remaining: remaining - 1, token: token)
                return [.scheduleTick(token: token)]
            }
            machine.state = .idle
            return [.startCapture]

        case (.counting, .sourceUnavailable(let reason)):
            machine.state = .idle
            return [.cancelTick, .notice(reason)]

        case (.idle, _):
            return []
        }
    }
}
