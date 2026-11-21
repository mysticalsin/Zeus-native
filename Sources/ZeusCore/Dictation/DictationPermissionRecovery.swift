import Foundation

/// What a dictation key press should do about the microphone and speech recognition.
/// `notDetermined` and `denied` are separate: one asks, the other opens Settings.
public enum DictationAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

public enum DictationPermissionPrompt: Equatable, Sendable {
    case microphone
    case speech
}

public enum DictationPermissionRecovery: Equatable, Sendable {
    case start
    case prompt(DictationPermissionPrompt)
    /// A refusal. `pane` is nil when the notch can only show text, with no Settings control.
    case showSettings(message: String, pane: String?)
}

public enum DictationPermissionGate {
    public static let microphonePane = "Privacy_Microphone"
    public static let speechPane = "Privacy_SpeechRecognition"

    /// A refused permission opens its privacy pane. A permission that was never asked is prompted.
    /// A local engine does not need speech recognition.
    public static func decide(microphone: DictationAccess, speech: DictationAccess, localEngineReady: Bool) -> DictationPermissionRecovery {
        switch microphone {
        case .notDetermined:
            return .prompt(.microphone)
        case .denied:
            return .showSettings(message: "Dictation needs the microphone.", pane: microphonePane)
        case .authorized:
            if localEngineReady || speech == .authorized { return .start }
            if speech == .notDetermined { return .prompt(.speech) }
            return .showSettings(message: "Dictation needs speech recognition.", pane: speechPane)
        }
    }
}
