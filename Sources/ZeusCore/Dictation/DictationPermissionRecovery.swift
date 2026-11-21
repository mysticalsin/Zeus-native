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

    /// Current behavior, kept so the failing test can name it: every refusal is text, and nothing asks.
    public static func decide(microphone: DictationAccess, speech: DictationAccess, localEngineReady: Bool) -> DictationPermissionRecovery {
        if microphone != .authorized {
            return .showSettings(message: "Dictation needs the microphone", pane: nil)
        }
        if localEngineReady || speech == .authorized { return .start }
        return .showSettings(message: "Speech recognition is unavailable", pane: nil)
    }
}
