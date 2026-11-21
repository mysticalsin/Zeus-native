import Foundation

/// The voice self-test already stops waiting for playback after 25 s. The sentence pump did not.
public enum ProviderClipWait {
    public static let limit: TimeInterval = 25

    public static func expired(started: Date, now: Date, limit: TimeInterval = ProviderClipWait.limit) -> Bool {
        now.timeIntervalSince(started) >= limit
    }
}

public enum CloudSentenceEnd: Equatable, Sendable {
    case spoken
    case failed
    case cancelled

    public static func decide(scheduledAudio: Bool, transportFailed: Bool, cancelled: Bool) -> CloudSentenceEnd {
        if cancelled { return .cancelled }
        if transportFailed { return .failed }
        return scheduledAudio ? .spoken : .failed
    }
}

/// Header waits use the existing first-audio timeout. The 15 s and 20 s request timeouts stay on the request.
public enum CloudHeaderWait {
    public static func shouldAbandon(began: Date, now: Date, receivedAudio: Bool,
                                     timeout: TimeInterval = VoiceTTSChain.firstAudioTimeout) -> Bool {
        guard !receivedAudio else { return false }
        return ElevenLabsFailsafe.firstAudioRemaining(began: began, now: now, timeout: timeout) == nil
    }
}
