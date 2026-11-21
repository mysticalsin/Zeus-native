import Foundation

/// Sentences a person can act on. The system error stays in the log.
public enum ShownFailure {
    public static let meetingSave = "Couldn't save this meeting. It is still here. Try again."
    public static let meetingNotes = "The notes couldn't be written, so only the transcript was saved."
    public static let dictationFile = "Couldn't read that file. Try another one."

    public static let missingKey = "An API key is missing. Add it in Settings, then try again."
    public static let revokedKey = "That API key was revoked. Add a new one in Settings, then try again."
    public static let microphoneDenied = "The microphone is off for Zeus. Turn it on in System Settings, then try again."
    public static let speechDenied = "Speech recognition is off for Zeus. Turn it on in System Settings, then try again."
    public static let fileDenied = "Zeus isn't allowed to use that file. Allow access, then try again."

    public static func engine(_ name: String) -> String {
        "\(name) couldn't transcribe that. Try again."
    }

    /// A key or permission problem with its own sentence. Anything else keeps the caller's fixed sentence.
    public enum Notice: Equatable, Sendable {
        case missingKey
        case revokedKey
        case microphoneDenied
        case speechDenied
        case fileDenied
    }

    public static func sentence(for notice: Notice) -> String {
        switch notice {
        case .missingKey: missingKey
        case .revokedKey: revokedKey
        case .microphoneDenied: microphoneDenied
        case .speechDenied: speechDenied
        case .fileDenied: fileDenied
        }
    }

    /// The words on screen. Never the system or provider text, even when `error` carries it.
    public static func sentence(for error: Error, otherwise fallback: String) -> String {
        guard let notice = notice(for: error) else { return fallback }
        return sentence(for: notice)
    }

    public static func notice(for error: Error) -> Notice? {
        classify(error, allowUnderlying: true)
    }

    /// What may be written to a private log: the system text, with key-shaped runs removed.
    public static func logDetail(_ error: Error) -> String {
        PrivateLogText.redact(systemText(error))
    }

    /// The description a log can keep. A Swift error's own sentence wins; otherwise the
    /// system text, including a description stored only on an `NSError`.
    private static func systemText(_ error: Error) -> String {
        if let described = error as? LocalizedError, let text = described.errorDescription, !text.isEmpty {
            return text
        }
        let ns = error as NSError
        if let text = ns.userInfo[NSLocalizedDescriptionKey] as? String, !text.isEmpty {
            return text
        }
        return ns.localizedDescription
    }

    private static func classify(_ error: Error, allowUnderlying: Bool) -> Notice? {
        if let cloud = error as? CloudTranscriptionError {
            switch cloud {
            case .missingKey: return .missingKey
            case .rejectedKey: return .revokedKey
            default: return nil
            }
        }
        let ns = error as NSError
        if let direct = notice(domain: ns.domain, code: ns.code) { return direct }
        if allowUnderlying, let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            return classify(underlying, allowUnderlying: false)
        }
        return nil
    }

    /// Codes that mean a denied permission. Other failures stay on the generic sentence.
    private static func notice(domain: String, code: Int) -> Notice? {
        if domain == NSCocoaErrorDomain {
            if code == CocoaError.Code.fileReadNoPermission.rawValue
                || code == CocoaError.Code.fileWriteNoPermission.rawValue {
                return .fileDenied
            }
        }
        // POSIX EACCES. A missing file is a different code and keeps the generic sentence.
        if domain == NSPOSIXErrorDomain && code == 13 { return .fileDenied }
        // Core Audio '!prm' (kAudioDevicePermissionsError): the device refused the microphone.
        if (domain == "NSOSStatusErrorDomain" || domain == "com.apple.coreaudio.avfaudio"), code == 561017453 {
            return .microphoneDenied
        }
        // Speech framework: the recognition request is not authorized.
        if domain == "kAFAssistantErrorDomain" && code == 1700 { return .speechDenied }
        return nil
    }
}
