/// Which update-feed check may still write the badge.
///
/// Every refresh (hourly poll, Dismiss, the auto-update toggle, the debug fake version) used to start its
/// own unordered task, each carrying the settings it read at the start. A slow check begun before the
/// person turned auto-update off could finish after the newer, faster one and bring the badge back.
/// Now the newest request is the only live one: starting another supersedes (and cancels) the old, and a
/// completion applies only if its token is still the live token.
public enum UpdateRefresh {
    public enum State: Equatable, Sendable {
        case idle
        case refreshing(token: UInt64)
    }

    public enum Event: Equatable, Sendable {
        case requested(token: UInt64)
        case completed(token: UInt64)
        /// Something else decided the badge (a synchronous refresh) or the owner stopped.
        case invalidated
    }

    public enum Effect: Equatable, Sendable {
        case startFetch(token: UInt64)
        case cancelFetch(token: UInt64)
        /// The fetch for this token is current: write its result.
        case apply(token: UInt64)
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch (state, event) {
        case (.idle, .requested(let token)):
            return (.refreshing(token: token), [.startFetch(token: token)])
        case (.refreshing(let old), .requested(let token)):
            return (.refreshing(token: token), [.cancelFetch(token: old), .startFetch(token: token)])
        case (.refreshing(let live), .completed(let token)) where token == live:
            return (.idle, [.apply(token: token)])
        case (_, .completed):
            return (state, [])
        case (.refreshing(let live), .invalidated):
            return (.idle, [.cancelFetch(token: live)])
        case (.idle, .invalidated):
            return (.idle, [])
        }
    }
}
