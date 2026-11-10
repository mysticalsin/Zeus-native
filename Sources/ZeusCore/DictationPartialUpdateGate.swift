/// Acceptance gate for queued live dictation UI updates.
///
/// Both identities are required because SpeechInput sessions and controller turns have
/// independent lifetimes. Call this when the queued update executes, not when it is enqueued.
public enum DictationPartialUpdateGate {
    public static func accepts(
        queuedSpeechSessionID: Int,
        queuedControllerGeneration: UInt64,
        activeSpeechSessionID: Int?,
        activeControllerGeneration: UInt64?,
        currentControllerGeneration: UInt64
    ) -> Bool {
        guard let activeSpeechSessionID, let activeControllerGeneration else { return false }
        return queuedSpeechSessionID == activeSpeechSessionID
            && queuedControllerGeneration == activeControllerGeneration
            && queuedControllerGeneration == currentControllerGeneration
    }
}
