import Foundation

/// What went wrong with one ElevenLabs request.
public enum ElevenLabsFailure: Equatable, Sendable {
    /// The server answered with this HTTP status.
    case status(Int)
    /// No usable answer: network error, no audio, or the first-audio deadline passed.
    case unreachable
}

/// Pause bookkeeping for ElevenLabs with an injectable clock. A refused request (401, 402, 429, 5xx) is
/// persisted by the caller; an unreachable one is kept in memory only.
public struct ElevenLabsPause: Equatable, Sendable {
    public private(set) var persistedUntil: Date?
    public private(set) var transientUntil: Date?

    public init(persistedUntil: Date? = nil, transientUntil: Date? = nil) {
        self.persistedUntil = persistedUntil
        self.transientUntil = transientUntil
    }

    public func isPaused(now: Date) -> Bool {
        UltronVoicePlan.isPaused(until: persistedUntil, now: now) || UltronVoicePlan.isPaused(until: transientUntil, now: now)
    }

    public mutating func note(_ failure: ElevenLabsFailure, now: Date) {
        switch failure {
        case .status(let code): persistedUntil = Self.later(persistedUntil, now.addingTimeInterval(UltronVoicePlan.pauseSeconds(status: code)))
        case .unreachable: transientUntil = Self.later(transientUntil, now.addingTimeInterval(UltronVoicePlan.pauseSeconds(status: nil)))
        }
    }

    /// A later failure never shortens a pause that is still running.
    private static func later(_ current: Date?, _ new: Date) -> Date { max(current ?? .distantPast, new) }

    /// A stream that really played, or a changed key.
    public mutating func clear() {
        persistedUntil = nil
        transientUntil = nil
    }
}

/// The first-audio deadline decisions `Speaker` makes while it walks ElevenLabs routes and models.
public enum ElevenLabsFailsafe {
    /// Seconds left before `began + timeout`, or nil once the deadline has passed.
    public static func firstAudioRemaining(began: Date, now: Date, timeout: TimeInterval = VoiceTTSChain.firstAudioTimeout) -> TimeInterval? {
        let left = began.addingTimeInterval(timeout).timeIntervalSince(now)
        return left > 0 ? left : nil
    }

    /// Another route (the worker after the direct key) is tried only while the deadline has not passed.
    public static func shouldTryNextRoute(remaining: TimeInterval?) -> Bool { remaining != nil }

    /// The Studio model falls back to the fast model once, only while ElevenLabs is neither paused nor past its deadline.
    public static func shouldRetryOnFastModel(paused: Bool, remaining: TimeInterval?, answerHadAudio: Bool) -> Bool {
        !paused && remaining != nil && !answerHadAudio
    }

    /// A partial chunk at the deadline is a fragment, not a reply: it is discarded and counts as a failure.
    public static func shouldPushPartialChunk(remaining: TimeInterval?) -> Bool { remaining != nil }

    /// Automatic unless the owner explicitly wrote `voice.engine.auto`. A stored provider alone, such as one
    /// carried in by a settings import, does not turn automatic off (picking an engine writes the flag).
    public static func defaultEngineAuto(explicit: Bool?, storedProvider: String?) -> Bool {
        explicit ?? true
    }
}
