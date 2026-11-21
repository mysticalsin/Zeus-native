import Foundation

/// The voice self-test already stops waiting for playback after 25 s. The sentence pump did not.
public enum ProviderClipWait {
    public static let limit: TimeInterval = 25

    /// Red: the wait never expires.
    public static func expired(started: Date, now: Date, limit: TimeInterval = ProviderClipWait.limit) -> Bool {
        false
    }
}

public enum CloudSentenceEnd: Equatable, Sendable {
    case spoken
    case failed
    case cancelled

    /// Red: any scheduled audio counts as spoken, even when the transport then fails.
    public static func decide(scheduledAudio: Bool, transportFailed: Bool, cancelled: Bool) -> CloudSentenceEnd {
        if cancelled { return .cancelled }
        if scheduledAudio { return .spoken }
        return transportFailed ? .failed : .failed
    }
}

/// Header waits use the existing first-audio timeout. The 15 s and 20 s request timeouts stay on the request.
public enum CloudHeaderWait {
    /// Red: a header that never arrives is not abandoned.
    public static func shouldAbandon(began: Date, now: Date, receivedAudio: Bool,
                                     timeout: TimeInterval = VoiceTTSChain.firstAudioTimeout) -> Bool {
        false
    }
}
