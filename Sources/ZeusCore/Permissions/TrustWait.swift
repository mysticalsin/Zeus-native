/// Features that need Accessibility and wait for it, as one list of keys plus a poll that runs only
/// while the list is not empty.
///
/// The gate kept a bare array of closures and a timer. A feature that asked twice (restarted, turned
/// off and on) was queued twice and started twice when access arrived, and a feature turned off while
/// waiting stayed queued, so the 3 s poll ran for as long as Zeus did. Each waiter now has a key:
/// asking again replaces it, `cancelled` removes it, and the poll stops with the last waiter.
public enum TrustWait {
    public struct State: Equatable, Sendable {
        /// Keys in the order they first asked.
        public var waiting: [String] = []
        public var polling = false
        public init() {}
    }

    public enum Event: Equatable, Sendable {
        /// `key` needs Accessibility. `trusted` is the answer right now.
        case wanted(key: String, trusted: Bool)
        /// The feature behind `key` no longer needs it.
        case cancelled(key: String)
        /// The poll found Accessibility granted.
        case becameTrusted
    }

    public enum Effect: Equatable, Sendable {
        /// Access is already there: run this feature's start now.
        case run(key: String)
        case startPolling
        case stopPolling
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        var next = state
        switch event {
        case .wanted(let key, let trusted):
            if trusted { return (state, [.run(key: key)]) }
            if !next.waiting.contains(key) { next.waiting.append(key) }
            guard !next.polling else { return (next, []) }
            next.polling = true
            return (next, [.startPolling])

        case .cancelled(let key):
            next.waiting.removeAll { $0 == key }
            guard next.waiting.isEmpty, next.polling else { return (next, []) }
            next.polling = false
            return (next, [.stopPolling])

        case .becameTrusted:
            let ready = next.waiting
            next.waiting = []
            let wasPolling = next.polling
            next.polling = false
            var effects: [Effect] = []
            if wasPolling { effects.append(.stopPolling) }
            for key in ready { effects.append(.run(key: key)) }
            return (next, effects)
        }
    }
}
