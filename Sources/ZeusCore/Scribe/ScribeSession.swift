import Foundation

public enum ScribePhase: Equatable, Sendable {
    case idle
    case starting(ScribeSessionID)
    case recording(ScribeSessionID, since: TimeInterval)
    case ending(ScribeSessionID, deadline: TimeInterval)
    case processing(ScribeSessionID)
    case complete(ScribeSessionID)
    case failed(ScribeSessionID, reason: String)

    public var sessionID: ScribeSessionID? {
        switch self {
        case .idle: return nil
        case .starting(let id), .processing(let id), .complete(let id): return id
        case .recording(let id, _), .ending(let id, _), .failed(let id, _): return id
        }
    }

    /// True while a session owns capture or processing (not idle and not terminal).
    public var isActive: Bool {
        switch self {
        case .starting, .recording, .ending, .processing: return true
        case .idle, .complete, .failed: return false
        }
    }
}

/// The only triggers a UI may animate on. Nothing here is produced by a timer faking success.
public enum ScribeLifecycleEvent: Equatable, Sendable {
    case recordingStarted(ScribeSessionID)
    case endingCountdown(ScribeSessionID, remaining: TimeInterval)
    case endingCancelled(ScribeSessionID)
    case recordingEnded(ScribeSessionID)
    case transcriptUpdated(ScribeSessionID)
    case transcriptFinalized(ScribeSessionID)
    case notesReady(ScribeSessionID)
    case cancelled(ScribeSessionID)
    case failed(ScribeSessionID, reason: String)
}

public struct ScribeTransition: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The command changed state (or emitted events).
        case applied
        /// The command named a session that is not current. No state change.
        case stale
        /// The command named the current session but is not valid in this phase. No state change.
        case invalid
    }

    public let outcome: Outcome
    public let events: [ScribeLifecycleEvent]

    public var isApplied: Bool { outcome == .applied }

    static func applied(_ events: [ScribeLifecycleEvent] = []) -> ScribeTransition {
        ScribeTransition(outcome: .applied, events: events)
    }

    static let stale = ScribeTransition(outcome: .stale, events: [])
    static let invalid = ScribeTransition(outcome: .invalid, events: [])
}

/// Pure session state machine. Capture is "recording" only after the provider acknowledged it,
/// and capture ends only when the provider reports it ended. Countdown expiry alone ends nothing.
public struct ScribeSessionMachine: Equatable, Sendable {
    public private(set) var phase: ScribePhase = .idle
    public private(set) var startedAt: TimeInterval?
    private var recordingSince: TimeInterval = 0
    private var transcriptDone = false
    private var notesDone = false

    public init() {}

    /// Starts a session. If another session is active it is replaced: `.cancelled(old)` is emitted.
    public mutating func start(_ id: ScribeSessionID, now: TimeInterval) -> ScribeTransition {
        var events: [ScribeLifecycleEvent] = []
        if phase.sessionID == id { return .invalid }
        if phase.isActive, let old = phase.sessionID {
            events.append(.cancelled(old))
        }
        phase = .starting(id)
        startedAt = now
        recordingSince = now
        transcriptDone = false
        notesDone = false
        return .applied(events)
    }

    public mutating func acknowledgeCapture(_ id: ScribeSessionID, now: TimeInterval) -> ScribeTransition {
        guard phase.sessionID == id else { return .stale }
        guard case .starting = phase else { return .invalid }
        recordingSince = now
        phase = .recording(id, since: now)
        return .applied([.recordingStarted(id)])
    }

    public mutating func requestEnd(_ id: ScribeSessionID, now: TimeInterval, grace: TimeInterval) -> ScribeTransition {
        guard phase.sessionID == id else { return .stale }
        guard case .recording = phase else { return .invalid }
        let window = max(0, grace)
        phase = .ending(id, deadline: now + window)
        return .applied([.endingCountdown(id, remaining: window)])
    }

    /// Reports countdown progress. Never changes phase, even after the deadline.
    public mutating func tick(now: TimeInterval) -> ScribeTransition {
        guard case .ending(let id, let deadline) = phase else { return .invalid }
        return .applied([.endingCountdown(id, remaining: max(0, deadline - now))])
    }

    public func isCountdownExpired(now: TimeInterval) -> Bool {
        guard case .ending(_, let deadline) = phase else { return false }
        return now >= deadline
    }

    public mutating func keepRecording(_ id: ScribeSessionID) -> ScribeTransition {
        guard phase.sessionID == id else { return .stale }
        guard case .ending = phase else { return .invalid }
        phase = .recording(id, since: recordingSince)
        return .applied([.endingCancelled(id)])
    }

    /// The provider reports capture is over (we asked, or the call ended on its own).
    public mutating func captureEnded(_ id: ScribeSessionID) -> ScribeTransition {
        guard phase.sessionID == id else { return .stale }
        switch phase {
        case .recording, .ending:
            phase = .processing(id)
            return .applied([.recordingEnded(id)])
        default:
            return .invalid
        }
    }

    public mutating func transcriptUpdated(_ id: ScribeSessionID) -> ScribeTransition {
        guard phase.sessionID == id else { return .stale }
        switch phase {
        case .recording, .ending, .processing:
            return .applied([.transcriptUpdated(id)])
        default:
            return .invalid
        }
    }

    public mutating func transcriptFinalized(_ id: ScribeSessionID) -> ScribeTransition {
        guard phase.sessionID == id else { return .stale }
        guard case .processing = phase, !transcriptDone else { return .invalid }
        transcriptDone = true
        return .applied([.transcriptFinalized(id)])
    }

    /// Notes derive from the final transcript, so they are only accepted after it was finalized.
    public mutating func notesReady(_ id: ScribeSessionID) -> ScribeTransition {
        guard phase.sessionID == id else { return .stale }
        guard case .processing = phase, transcriptDone, !notesDone else { return .invalid }
        notesDone = true
        phase = .complete(id)
        return .applied([.notesReady(id)])
    }

    /// Production completion: an invalid/stale session cannot write a recap, and a failed save cannot
    /// emit a successful completion. The callback retains the unsaved payload for an explicit retry.
    public mutating func saveAndCompleteNotes(_ id: ScribeSessionID, save: () -> Bool) -> ScribeTransition {
        guard phase.sessionID == id else { return .stale }
        guard case .processing = phase, transcriptDone, !notesDone else { return .invalid }
        guard save() else { return .invalid }
        return notesReady(id)
    }

    public mutating func cancel(_ id: ScribeSessionID) -> ScribeTransition {
        guard phase.sessionID == id else { return .stale }
        guard phase.isActive else { return .invalid }
        phase = .idle
        return .applied([.cancelled(id)])
    }

    public mutating func fail(_ id: ScribeSessionID, reason: String) -> ScribeTransition {
        guard phase.sessionID == id else { return .stale }
        guard phase.isActive else { return .invalid }
        phase = .failed(id, reason: reason)
        return .applied([.failed(id, reason: reason)])
    }
}
