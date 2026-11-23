import Foundation

/// Which camera frames and signals still belong to the run that is on, and when vision
/// has failed often enough to fail the camera. The camera and the vault stay in the app.
public struct FaceFrameGate: Equatable, Sendable {
    public static let failureLimit = 5

    public enum State: Equatable, Sendable {
        case stopped
        case running(generation: Int, failures: Int)
    }

    public enum Change: Equatable, Sendable {
        case unchanged
        case started(Int)
        case stopped
    }

    public enum Failure: Equatable, Sendable {
        case failCamera
    }

    public private(set) var state: State

    public init() {
        state = .stopped
        stoppedGeneration = 0
    }

    public var generation: Int {
        switch state {
        case .stopped: stoppedGeneration
        case .running(let generation, _): generation
        }
    }

    public var failures: Int {
        if case .running(_, let failures) = state { return failures }
        return 0
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    private var stoppedGeneration: Int

    /// Turning the camera on or off starts a new generation. On clears the failure count.
    /// A second request for the same side does nothing.
    public mutating func setCamera(_ on: Bool) -> Change {
        if on {
            guard !isRunning else { return .unchanged }
            let next = generation + 1
            state = .running(generation: next, failures: 0)
            return .started(next)
        }
        guard isRunning else { return .unchanged }
        stoppedGeneration = generation + 1
        state = .stopped
        return .stopped
    }

    /// A frame or a camera signal counts only for the generation that is running.
    public func accepts(_ generation: Int) -> Bool {
        guard case .running(let current, _) = state else { return false }
        return generation == current
    }

    /// The failure that reaches the limit fails the camera once. Later failures wait for a good frame.
    public mutating func visionFailed() -> Failure? {
        guard case .running(let generation, let failures) = state else { return nil }
        let next = failures + 1
        state = .running(generation: generation, failures: next)
        return next == Self.failureLimit ? .failCamera : nil
    }

    public mutating func visionOk() {
        guard case .running(let generation, _) = state else { return }
        state = .running(generation: generation, failures: 0)
    }
}

/// The lowest "Face N" that is not already taken.
public enum FaceNameSequence {
    public static func next(taken: Set<String>) -> String {
        var number = 1
        while taken.contains("Face \(number)") { number += 1 }
        return "Face \(number)"
    }
}

/// An enrollment offer is heard only for the token that is open.
public struct EnrollmentOfferGate: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case offering(Int)
    }

    public private(set) var state: State

    public init() {
        state = .idle
    }

    public mutating func begin(_ token: Int) {
        state = .offering(token)
    }

    public mutating func offer(_ token: Int) -> Bool {
        guard case .offering(let current) = state else { return false }
        return current == token
    }

    public mutating func end() {
        state = .idle
    }
}
