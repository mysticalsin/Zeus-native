import Foundation

/// How long the music wings stay after a pause. An unknown label, and a delay that is not a
/// positive finite number, are at once.
public enum PauseCollapse: Equatable, Sendable {
    case atOnce
    case after(TimeInterval)
    case never

    public init(label: String) {
        switch label.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "At once": self = .atOnce
        case "After 10 s": self = .after(10)
        case "After 1 min": self = .after(60)
        case "Never": self = .never
        default: self = .atOnce
        }
    }

    public init(delay: TimeInterval) {
        if delay.isFinite, delay > 0 {
            self = .after(delay)
        } else {
            self = .atOnce
        }
    }
}

/// Whether the closed music wings stay up after the sound stops. Pure: the clock arrives in events.
public enum MusicWingsHold {
    public enum Playback: Equatable, Sendable {
        case none
        case playing
        case paused
    }

    public enum State: Equatable, Sendable {
        case hidden
        case playing
        case held(since: Date, until: Date?)
    }

    public enum Event: Equatable, Sendable {
        case playback(Playback, wingsOnScreen: Bool, now: Date)
        case wingsSwitchedOff
        case policy(PauseCollapse, now: Date)
        case deadline(now: Date)
    }

    public enum Effect: Equatable, Sendable {
        case wake(at: Date)
        case cancelWake
    }

    public static func showsWings(_ state: State) -> Bool {
        switch state {
        case .playing, .held: true
        case .hidden: false
        }
    }

    public static func isPaused(_ state: State) -> Bool {
        if case .held = state { return true }
        return false
    }

    /// `wingsOnScreen` is read only on the edge from playing to paused. A second pause keeps `since`.
    /// A time before that pause collapses the hold. An early deadline asks for the same wake again.
    public static func reduce(_ state: State, _ event: Event, policy: PauseCollapse) -> (State, [Effect]) {
        switch event {
        case .wingsSwitchedOff:
            if case .held = state { return (.hidden, [.cancelWake]) }
            return (.hidden, [])
        case .policy(let next, let now):
            guard case .held(let since, _) = state else { return (state, []) }
            return retimed(since: since, now: now, policy: next)
        case .deadline(let now):
            guard case .held(let since, let until) = state else { return (state, []) }
            if now < since { return (.hidden, [.cancelWake]) }
            guard let until else { return (state, []) }
            if now < until { return (state, [.wake(at: until)]) }
            return (.hidden, [.cancelWake])
        case .playback(let playback, let wingsOnScreen, let now):
            switch (state, playback) {
            case (_, .playing):
                if case .held = state { return (.playing, [.cancelWake]) }
                return (.playing, [])
            case (.playing, .paused):
                guard wingsOnScreen else { return (.hidden, []) }
                return begin(at: now, policy: policy)
            case (.playing, .none):
                return (.hidden, [])
            case (.held(let since, let until), .paused):
                if now < since { return (.hidden, [.cancelWake]) }
                return (.held(since: since, until: until), [])
            case (.held, .none):
                return (.hidden, [.cancelWake])
            case (.hidden, _):
                return (.hidden, [])
            }
        }
    }

    private static func begin(at now: Date, policy: PauseCollapse) -> (State, [Effect]) {
        switch normalized(policy) {
        case .atOnce:
            return (.hidden, [])
        case .never:
            return (.held(since: now, until: nil), [])
        case .after(let seconds):
            let until = now.addingTimeInterval(seconds)
            return (.held(since: now, until: until), [.wake(at: until)])
        }
    }

    private static func retimed(since: Date, now: Date, policy: PauseCollapse) -> (State, [Effect]) {
        if now < since { return (.hidden, [.cancelWake]) }
        switch normalized(policy) {
        case .atOnce:
            return (.hidden, [.cancelWake])
        case .never:
            return (.held(since: since, until: nil), [.cancelWake])
        case .after(let seconds):
            let until = since.addingTimeInterval(seconds)
            if now >= until { return (.hidden, [.cancelWake]) }
            return (.held(since: since, until: until), [.cancelWake, .wake(at: until)])
        }
    }

    private static func normalized(_ policy: PauseCollapse) -> PauseCollapse {
        if case .after(let seconds) = policy, !(seconds.isFinite && seconds > 0) {
            return .atOnce
        }
        return policy
    }
}
