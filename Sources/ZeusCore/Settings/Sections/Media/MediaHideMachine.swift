import Foundation

/// How the player leaves after a pause. Never is the behaviour the notch has today.
public enum MediaHidePolicy: String, CaseIterable, Sendable, Equatable {
    case instantly
    case afterDelay
    case never

    /// How long After a delay waits. The wait is a behaviour, not an animation.
    public static let delay: TimeInterval = 5

    public var title: String {
        switch self {
        case .instantly: "Instantly"
        case .afterDelay: "After a delay"
        case .never: "Never"
        }
    }

    public init(stored: String?) {
        self = Self(rawValue: stored ?? "") ?? .never
    }
}

/// What one hide step did. A rejected event changes nothing and does not animate.
public struct MediaHideStep: Equatable, Sendable {
    public var state: MediaHideMachine.State
    public var accepted: Bool
    public var animationDuration: TimeInterval
    public var visible: Bool

    public init(state: MediaHideMachine.State, accepted: Bool, animationDuration: TimeInterval, visible: Bool) {
        self.state = state
        self.accepted = accepted
        self.animationDuration = animationDuration
        self.visible = visible
    }
}

/// Shown, waiting out the pause delay, or hidden. A pause is accepted only from shown.
public struct MediaHideMachine: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case visible
        case counting(since: Date)
        case hidden
    }

    public enum Event: Equatable, Sendable {
        case beganPlaying
        case paused(at: Date)
        case timePassed(at: Date)
        case policy(MediaHidePolicy)
        /// Nothing on screen is not a pause, so the player comes back.
        case cleared
    }

    public private(set) var state: State
    public private(set) var policy: MediaHidePolicy

    public init(policy: MediaHidePolicy = .never, state: State = .visible) {
        self.policy = policy
        self.state = state
    }

    public mutating func send(_ event: Event, reduceMotion: Bool) -> MediaHideStep {
        let before = state
        let accepted: Bool
        switch event {
        case .beganPlaying:
            state = .visible
            accepted = true
        case .paused(let date):
            switch state {
            case .visible:
                accepted = true
                switch policy {
                case .instantly: state = .hidden
                case .never: break
                case .afterDelay: state = .counting(since: date)
                }
            case .counting, .hidden:
                accepted = false
            }
        case .timePassed(let date):
            guard case .counting(let since) = state else {
                accepted = false
                break
            }
            guard date >= since else {
                accepted = false
                break
            }
            accepted = true
            if date.timeIntervalSince(since) >= MediaHidePolicy.delay { state = .hidden }
        case .policy(let next):
            accepted = true
            policy = next
            switch state {
            case .visible:
                break
            case .counting:
                switch next {
                case .instantly: state = .hidden
                case .never: state = .visible
                case .afterDelay: break
                }
            case .hidden:
                if next == .never { state = .visible }
            }
        case .cleared:
            accepted = true
            state = .visible
        }
        let moved = state != before
        let duration = moved && !reduceMotion ? MotionTokens.panelClose.response : 0
        return MediaHideStep(state: state, accepted: accepted, animationDuration: duration, visible: state != .hidden)
    }

    /// Apply a new policy to a player that is already playing or already paused.
    @discardableResult
    public static func retarget(_ machine: inout MediaHideMachine, to policy: MediaHidePolicy, playing: Bool, at date: Date, reduceMotion: Bool) -> MediaHideStep {
        _ = machine.send(.policy(policy), reduceMotion: reduceMotion)
        if playing { return machine.send(.beganPlaying, reduceMotion: reduceMotion) }
        return machine.send(.paused(at: date), reduceMotion: reduceMotion)
    }
}
