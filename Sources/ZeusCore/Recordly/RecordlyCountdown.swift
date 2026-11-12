import Foundation

/// The 3, 2, 1 that runs between pressing Record and the capture starting. Pure: the controller owns one value,
/// performs the returned effects (one one-shot timer per step, then the real start), and tags every timer with the
/// token it was given so a tick from a cancelled countdown does nothing.
public struct RecordlyCountdown: Equatable, Sendable {
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

    public private(set) var state: State = .idle
    private var nextToken: UInt64 = 0

    public init() {}

    public var isCounting: Bool { if case .counting = state { true } else { false } }

    public var remaining: Int? {
        if case .counting(let remaining, _) = state { remaining } else { nil }
    }

    public static let noSourceNotice = "Choose a display or window first."
    public static let sourceLostNotice = "The source went away before recording started. Choose it again."

    public mutating func send(_ event: Event) -> [Effect] {
        switch (state, event) {
        case (.idle, .press(let ready)):
            guard ready else { return [.notice(Self.noSourceNotice)] }
            nextToken &+= 1
            state = .counting(remaining: Self.seconds, token: nextToken)
            return [.scheduleTick(token: nextToken)]

        case (.counting, .press), (.counting, .cancel):
            state = .idle
            return [.cancelTick]

        case (.counting(let remaining, let token), .tick(let tickToken, let sourceReady)):
            guard tickToken == token else { return [] }
            guard sourceReady else {
                state = .idle
                return [.cancelTick, .notice(Self.sourceLostNotice)]
            }
            if remaining > 1 {
                state = .counting(remaining: remaining - 1, token: token)
                return [.scheduleTick(token: token)]
            }
            state = .idle
            return [.startCapture]

        case (.counting, .sourceUnavailable(let reason)):
            state = .idle
            return [.cancelTick, .notice(reason)]

        case (.idle, _):
            return []
        }
    }
}
