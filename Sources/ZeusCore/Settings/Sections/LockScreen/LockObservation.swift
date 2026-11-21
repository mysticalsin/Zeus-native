import Foundation

/// What Zeus has observed about the session lock. A lost reading returns to `unknown`.
public enum LockObservation: String, Equatable, Sendable, CaseIterable {
    case unknown
    case unlocked
    case locking
    case locked
    case unlocking
}

/// One observation. The machine never starts a lock and never unlocks the Mac.
public enum LockObservationEvent: Equatable, Sendable, CaseIterable {
    case sawUnknown
    case sawUnlocked
    case sawLocked
    case beganLocking
    case beganUnlocking
    case cancelled
}

/// The lock and unlock observation. One state, and a guarded step for every event.
public struct LockObservationMachine: Equatable, Sendable {
    public private(set) var state: LockObservation

    public init(state: LockObservation = .unknown) {
        self.state = state
    }

    public mutating func handle(_ event: LockObservationEvent) {
        state = Self.step(state, event)
    }

    public static func step(_ state: LockObservation, _ event: LockObservationEvent) -> LockObservation {
        switch (state, event) {
        case (.unknown, .sawUnknown), (.unknown, .cancelled):
            return .unknown
        case (.unknown, .sawUnlocked):
            return .unlocked
        case (.unknown, .sawLocked):
            return .locked
        case (.unknown, .beganLocking):
            return .locking
        case (.unknown, .beganUnlocking):
            return .unlocking

        case (.unlocked, .sawUnknown):
            return .unknown
        case (.unlocked, .sawUnlocked), (.unlocked, .beganUnlocking), (.unlocked, .cancelled):
            return .unlocked
        case (.unlocked, .sawLocked):
            return .locked
        case (.unlocked, .beganLocking):
            return .locking

        case (.locking, .sawUnknown):
            return .unknown
        case (.locking, .sawUnlocked), (.locking, .cancelled):
            return .unlocked
        case (.locking, .sawLocked):
            return .locked
        case (.locking, .beganLocking):
            return .locking
        case (.locking, .beganUnlocking):
            return .unlocking

        case (.locked, .sawUnknown):
            return .unknown
        case (.locked, .sawUnlocked):
            return .unlocked
        case (.locked, .sawLocked), (.locked, .beganLocking), (.locked, .cancelled):
            return .locked
        case (.locked, .beganUnlocking):
            return .unlocking

        case (.unlocking, .sawUnknown):
            return .unknown
        case (.unlocking, .sawUnlocked):
            return .unlocked
        case (.unlocking, .sawLocked), (.unlocking, .cancelled):
            return .locked
        case (.unlocking, .beganLocking):
            return .locking
        case (.unlocking, .beganUnlocking):
            return .unlocking
        }
    }
}
