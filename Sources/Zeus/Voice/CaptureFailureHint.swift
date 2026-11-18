import Foundation

/// What a talk turn or a dictation tells the person when the microphone capture gives up under it,
/// and which callbacks still belong to the running turn.
enum CaptureFailureHint {
    static func text(for failure: SpeechInput.CaptureFailure) -> String {
        switch failure {
        case .configurationChanged: "The microphone kept changing, so Zeus stopped listening. Try again."
        case .durationLimit, .sampleLimit: "That recording got too long, so Zeus stopped listening. Try again."
        }
    }

    /// A late or replaced session never ends a newer turn.
    static func owns(session: Int, active: Int?) -> Bool { active == session }
}
