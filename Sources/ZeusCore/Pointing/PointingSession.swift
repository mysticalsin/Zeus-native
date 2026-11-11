import Foundation

/// Lifecycle of one pointing session. Pure. Every transition that starts new work bumps
/// `generation`; callers pass the generation they captured, and late callbacks that carry an
/// older one are dropped (the same pattern as `ExplanationController.generation`).
public struct PointingSession: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle, listening, drawing, processing, speaking
        /// Guided-click wait. Stubbed in Phase 1: nothing sends `guidanceAdmitted` yet.
        case guiding
        case interrupted, cancelled
        case failed(String)
    }

    public enum Event: Equatable, Sendable {
        case keyDown
        case keyUp
        case spoiled
        case escape
        case strokeBegan, strokeEnded
        case emptyTranscript
        case firstPlaybackStart
        case buffering
        case guidanceAdmitted
        case clickInTarget
        case turnCompleted
        case permissionLost
        case failure(String)
        /// Cleanup of a cancelled, interrupted or failed turn is done.
        case cleanedUp
    }

    /// Work the caller must perform for a transition.
    public enum Effect: Equatable, Sendable {
        case stopOutput        // stop speech, pending animation, and any capture
        case startListening
        case stopListening     // mic.finish(): build the request
        case discardCapture    // cancel the mic, discard audio, send nothing
        case hideInk
    }

    public struct Transition: Equatable, Sendable {
        public var from: State
        public var to: State
        public var generation: Int
        public var effects: [Effect]
        public var changed: Bool { from != to || !effects.isEmpty }
    }

    public private(set) var state: State = .idle
    public private(set) var generation = 0

    public init() {}

    public func isCurrent(_ token: Int) -> Bool { token == generation }

    /// `generation`: the token the sender captured; a mismatch drops the event.
    @discardableResult
    public mutating func send(_ event: Event, generation token: Int? = nil) -> Transition {
        let from = state
        if let token, token != generation { return Transition(from: from, to: from, generation: generation, effects: []) }
        var effects: [Effect] = []
        var next = from
        switch (from, event) {
        case (.idle, .keyDown), (.interrupted, .keyDown), (.cancelled, .keyDown), (.failed, .keyDown):
            next = .listening; generation += 1; effects = [.startListening]
        case (.processing, .keyDown), (.speaking, .keyDown), (.guiding, .keyDown):
            // Barge-in: stop everything the previous turn was doing, then listen.
            next = .listening; generation += 1; effects = [.stopOutput, .startListening]
        case (.listening, .strokeBegan): next = .drawing
        case (.drawing, .strokeEnded): next = .listening
        case (.listening, .keyUp), (.drawing, .keyUp):
            next = .processing; generation += 1; effects = [.stopListening, .hideInk]
        case (.listening, .spoiled), (.drawing, .spoiled), (.listening, .escape), (.drawing, .escape):
            next = .cancelled; generation += 1; effects = [.discardCapture, .hideInk]
        case (.processing, .emptyTranscript):
            next = .cancelled; generation += 1; effects = [.discardCapture]
        case (.processing, .firstPlaybackStart): next = .speaking
        case (.speaking, .buffering): next = .processing
        case (.speaking, .guidanceAdmitted): next = .guiding
        case (.guiding, .clickInTarget): next = .processing; generation += 1
        case (.processing, .turnCompleted), (.speaking, .turnCompleted), (.guiding, .turnCompleted):
            next = .idle
        case (.processing, .escape), (.speaking, .escape), (.guiding, .escape):
            next = .interrupted; generation += 1; effects = [.stopOutput]
        case (.cancelled, .cleanedUp), (.interrupted, .cleanedUp), (.failed, .cleanedUp):
            next = .idle
        case (.idle, _):
            break
        case (_, .permissionLost):
            next = .failed("Access was turned off."); generation += 1
            effects = [.discardCapture, .stopOutput, .hideInk]
        case (_, .failure(let reason)):
            next = .failed(reason); generation += 1
            effects = [.discardCapture, .stopOutput, .hideInk]
        default:
            break
        }
        state = next
        return Transition(from: from, to: next, generation: generation, effects: effects)
    }
}
