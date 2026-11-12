import Intents
import Speech

/// System permission requests whose completion handlers arrive on a TCC background queue.
///
/// A handler closure written inside a `@MainActor` type inherits main-actor isolation, and Swift 6
/// traps when TCC calls it off the main thread ("Incorrect actor executor assumption"). That crashed
/// onboarding's voice step on first launch. These functions are nonisolated, so their handlers carry
/// no actor isolation and only resume a continuation. Callers on any actor simply `await` them.
/// A closed-loop source lint keeps every other file from calling these APIs with a handler.
enum SystemAuthorization {
    nonisolated static func requestSpeechRecognition() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
        }
    }

    nonisolated static func requestFocusStatus() async -> INFocusStatusAuthorizationStatus {
        await withCheckedContinuation { continuation in
            INFocusStatusCenter.default.requestAuthorization { status in continuation.resume(returning: status) }
        }
    }
}
