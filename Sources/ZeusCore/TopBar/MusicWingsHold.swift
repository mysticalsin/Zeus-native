import Foundation

/// How long the music wings stay after a pause. An unknown label, and a delay that is not a
/// positive finite number, are at once. The choice is read from `MusicWingsHoldBox`.
public enum PauseCollapse: Equatable, Sendable {
    case atOnce
    case after(TimeInterval)
    case never

    public init(label: String) {
        self = MusicWingsHoldBox.collapse(label: label)
    }

    public init(delay: TimeInterval) {
        self = MusicWingsHoldBox.collapse(delay: delay)
    }
}

/// Whether the closed music wings stay up after the sound stops. Pure: the clock arrives in events.
/// Each answer is read from `MusicWingsHoldBox`.
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
        MusicWingsHoldBox.showsWings(state)
    }

    public static func isPaused(_ state: State) -> Bool {
        MusicWingsHoldBox.isPaused(state)
    }

    public static func reduce(_ state: State, _ event: Event, policy: PauseCollapse) -> (State, [Effect]) {
        MusicWingsHoldBox.reduce(state, event, policy: policy)
    }
}
