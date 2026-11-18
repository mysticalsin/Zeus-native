import Foundation

/// What a talk turn or a dictation tells the person when the microphone capture gives up under it,
/// and which callbacks still belong to the running turn.
enum CaptureFailureHint {
    static func text(for failure: SpeechInput.CaptureFailure) -> String {
        switch failure {
        case .configurationChanged: "The microphone kept changing, so Zeus stopped listening. Try again."
        // Talk and dictation set no length limit, so only the explanation capture reaches these two.
        // They are worded anyway so a future limit never shows an empty hint.
        case .durationLimit, .sampleLimit: "That recording got too long, so Zeus stopped listening. Try again."
        }
    }

    /// A late or replaced session never ends a newer turn.
    static func owns(session: Int, active: Int?) -> Bool { active == session }
}

/// Remembers the capture failure of a speech session from whichever thread reports it, so the talk key's
/// release can see it before the main-actor handling has run.
final class CaptureFailureLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: (session: Int, failure: SpeechInput.CaptureFailure)?

    func record(session: Int, failure: SpeechInput.CaptureFailure) {
        lock.withLock { recorded = (session, failure) }
    }

    func failure(for session: Int) -> SpeechInput.CaptureFailure? {
        lock.withLock { recorded?.session == session ? recorded?.failure : nil }
    }

    func reset() { lock.withLock { recorded = nil } }
}
