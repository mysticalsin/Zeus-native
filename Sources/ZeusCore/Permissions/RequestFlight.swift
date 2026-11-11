/// One consent request in flight at a time, per thing being asked for.
///
/// Before this model each permission prompt carried its own `asking` Bool (or none): a double click
/// on "Turn on" asked macOS twice, and a second caller that found the flag set returned before the
/// answer existed. Now the request is a state: the first request begins, every later request while it
/// is asking joins it, and only the matching token can finish it.
public enum RequestFlight {
    public enum State: Equatable, Sendable {
        case idle
        case asking(token: UInt64)
    }

    public enum Event: Equatable, Sendable {
        /// Someone wants the answer. `token` is used only if nothing is asking yet.
        case requested(token: UInt64)
        /// The request that began with `token` has an answer (granted, refused or failed).
        case finished(token: UInt64)
        /// The owner is going away: no answer will be waited on.
        case abandoned
    }

    public enum Effect: Equatable, Sendable {
        /// Raise the prompt now.
        case begin(token: UInt64)
        /// A prompt is already up: wait for it instead of raising another.
        case join(token: UInt64)
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch (state, event) {
        case (.idle, .requested(let token)):
            return (.asking(token: token), [.begin(token: token)])
        case (.asking(let current), .requested):
            return (state, [.join(token: current)])
        case (.asking(let current), .finished(let token)) where token == current:
            return (.idle, [])
        case (_, .finished):
            return (state, [])
        case (_, .abandoned):
            return (.idle, [])
        }
    }
}

/// `RequestFlight` for several independent keys ("voice", "camera", a website host), with the tokens
/// handed out here so callers never invent their own.
public struct RequestFlights<Key: Hashable & Sendable>: Sendable {
    private var states: [Key: RequestFlight.State] = [:]
    private var lastToken: UInt64 = 0

    public init() {}

    public func state(_ key: Key) -> RequestFlight.State { states[key] ?? .idle }
    public func isAsking(_ key: Key) -> Bool { state(key) != .idle }

    /// `.begin` for the first asker; `.join` for everyone who arrives while it is asking.
    public mutating func request(_ key: Key) -> RequestFlight.Effect {
        lastToken &+= 1
        let (next, effects) = RequestFlight.reduce(state(key), .requested(token: lastToken))
        states[key] = next
        return effects[0]
    }

    /// True when `token` was the live request and it is now finished; a stale token changes nothing.
    @discardableResult
    public mutating func finish(_ key: Key, token: UInt64) -> Bool {
        let before = state(key)
        let (next, _) = RequestFlight.reduce(before, .finished(token: token))
        states[key] = next == .idle ? nil : next
        return before != next
    }

    public mutating func abandon(_ key: Key) { states[key] = nil }
    public mutating func abandonAll() { states.removeAll() }
}
