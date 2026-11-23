import Foundation

/// The ordered checklist around one manual scribe start. The controller still performs each effect.
public struct ScribeManualStart: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case clearing
        case wired
        case accepted
        case refused
    }

    public enum Effect: Equatable, Sendable {
        case refuse
        case yieldCapture
        case clearFields
        case openStreams
        case applyStart
        case startProvider
    }

    public private(set) var state: State

    public init() {
        state = .idle
    }

    /// An active session stays idle and presents nothing to clear. A quiet session clears, then opens streams.
    public mutating func request(active: Bool) -> [Effect] {
        if active {
            state = .idle
            return [.refuse]
        }
        guard state == .idle || state == .accepted || state == .refused else { return [] }
        state = .clearing
        return [.yieldCapture, .clearFields, .openStreams]
    }

    /// Clear has finished. Streams are still unopened, and nothing new is emitted.
    public mutating func fieldsCleared() -> [Effect] {
        guard state == .clearing else { return [] }
        return []
    }

    /// Streams are open. The machine may now be asked to start.
    public mutating func wired() -> [Effect] {
        guard state == .clearing else { return [] }
        state = .wired
        return [.applyStart]
    }

    /// A refused apply starts no provider. An accepted apply starts it once.
    public mutating func machineApplied(_ applied: Bool) -> [Effect] {
        guard state == .wired else { return [] }
        if applied {
            state = .accepted
            return [.startProvider]
        }
        state = .refused
        return []
    }
}
