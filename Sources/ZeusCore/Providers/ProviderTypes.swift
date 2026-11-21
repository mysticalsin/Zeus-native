import Foundation

/// What a plug-in can do. Speech and language are reserved so a later adapter can register
/// without a second registry. Only text-to-speech has adapters today.
public enum ProviderKind: String, Sendable, CaseIterable, Equatable, Hashable {
    case tts
    case stt
    case llm
}

public struct ProviderCapabilities: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let listVoices = ProviderCapabilities(rawValue: 1 << 0)
    public static let streamingSynthesis = ProviderCapabilities(rawValue: 1 << 1)
    public static let validateCredential = ProviderCapabilities(rawValue: 1 << 2)
}

public struct CredentialField: Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var label: String
    public var masked: Bool
    public init(id: String, label: String, masked: Bool) {
        self.id = id
        self.label = label
        self.masked = masked
    }
}

public struct ProviderDescriptor: Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var displayName: String
    public var kind: ProviderKind
    public var credentialFields: [CredentialField]
    public var docsURL: URL
    public var capabilities: ProviderCapabilities
    public init(id: String, displayName: String, kind: ProviderKind, credentialFields: [CredentialField], docsURL: URL, capabilities: ProviderCapabilities) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.credentialFields = credentialFields
        self.docsURL = docsURL
        self.capabilities = capabilities
    }
}

public struct ProviderVoice: Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var language: String?
    public init(id: String, name: String, language: String?) {
        self.id = id
        self.name = name
        self.language = language
    }
}

public struct AudioChunk: Equatable, Sendable {
    public var data: Data
    public var index: Int
    public var isLast: Bool
    public init(data: Data, index: Int, isLast: Bool) {
        self.data = data
        self.index = index
        self.isLast = isLast
    }
}

public struct ProviderCredential: Equatable, Sendable {
    public var fields: [String: String]
    public init(fields: [String: String]) { self.fields = fields }
    public func value(_ id: String) -> String? {
        let trimmed = fields[id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

public enum ProviderFailure: Error, Equatable, Sendable, Hashable {
    case unauthorized
    case creditsUsedUp
    case badVoice
    case rateLimited
    case server(Int)
    case timedOut
    case cancelled
    case invalidResponse
    case notHTTPS
    case missingCredential
    case notRegistered
    case offline

    public var logName: String {
        switch self {
        case .unauthorized: "unauthorized"
        case .creditsUsedUp: "credits-used-up"
        case .badVoice: "bad-voice"
        case .rateLimited: "rate-limited"
        case .server(let status): "server-\(status)"
        case .timedOut: "timed-out"
        case .cancelled: "cancelled"
        case .invalidResponse: "invalid-response"
        case .notHTTPS: "not-https"
        case .missingCredential: "missing-credential"
        case .notRegistered: "not-registered"
        case .offline: "offline"
        }
    }

    public var pill: String {
        switch self {
        case .unauthorized: "Key rejected"
        case .creditsUsedUp: "Credits are used up"
        case .badVoice: "That voice isn't available"
        case .rateLimited: "Rate limited"
        case .server: "Provider unavailable"
        case .timedOut: "Timed out"
        case .cancelled: "Cancelled"
        case .invalidResponse: "No audio"
        case .notHTTPS: "Blocked"
        case .missingCredential: "Needs a key"
        case .notRegistered: "Unavailable"
        case .offline: "Offline"
        }
    }

    /// Maps a status code. A 400 counts as a rejected key only while validating, because a synthesize
    /// call can return 400 for a bad voice name.
    public static func fromHTTPStatus(_ status: Int, validating: Bool = false) -> ProviderFailure {
        switch status {
        case 0: .offline
        case 401, 403: .unauthorized
        case 402: .creditsUsedUp
        case 400 where validating: .unauthorized
        case 400: .badVoice
        case 429: .rateLimited
        case 500...599: .server(status)
        default: .invalidResponse
        }
    }

    public static func wrap(_ error: Error) -> ProviderFailure {
        if let failure = error as? ProviderFailure { return failure }
        if error is CancellationError { return .cancelled }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorTimedOut { return .timedOut }
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return .cancelled }
        if ns.domain == NSURLErrorDomain && (ns.code == NSURLErrorNotConnectedToInternet || ns.code == NSURLErrorNetworkConnectionLost
            || ns.code == NSURLErrorCannotFindHost || ns.code == NSURLErrorCannotConnectToHost || ns.code == NSURLErrorDNSLookupFailed) {
            return .offline
        }
        return .invalidResponse
    }
}

/// A saved key is at least 8 characters after trimming and at most 256 UTF-8 bytes.
/// C0 controls, DEL, C1 controls (U+0080 through U+009F), whitespace, and the listed
/// format characters are refused. Empty and malformed keys are refused before any request
/// is built. The text of a refusal never includes the key.
public enum VoiceProviderKeyPolicy {
    /// Maximum UTF-8 byte length of a trimmed key.
    public static let maxLength = 256
    public static let minimumCharacters = 8

    public static func accepts(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: padding)
        guard trimmed.count >= minimumCharacters else { return false }
        guard trimmed.utf8.count <= maxLength else { return false }
        return trimmed.unicodeScalars.allSatisfy(allows)
    }

    /// ASCII space, tab, and newline only. C1, line separators, and format characters stay in the key so they are rejected.
    private static let padding = CharacterSet(charactersIn: " \t\n\r\u{000B}\u{000C}")

    static func allows(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if value < 0x20 || value == 0x7F { return false }
        if (0x80...0x9F).contains(value) { return false }
        if scalar.properties.isWhitespace { return false }
        if (0x200B...0x200F).contains(value) { return false }
        if (0x202A...0x202E).contains(value) { return false }
        if (0x2060...0x2064).contains(value) { return false }
        if value == 0xFEFF { return false }
        return true
    }
}

/// WAV, an ID3 tag, or an MP3 frame. Anything else is not audio and must not be played.
public enum VoiceAudioValidity {
    public static func isPlayable(_ data: Data) -> Bool {
        if data.starts(with: Data("RIFF".utf8)) { return data.count > 44 }
        if data.starts(with: Data("ID3".utf8)) { return data.count > 10 }
        if data.count > 1, data[data.startIndex] == 0xFF {
            let second = data[data.index(after: data.startIndex)]
            return (second & 0xE0) == 0xE0
        }
        return false
    }
}

public enum VoiceProviderChoice: Equatable, Sendable, Hashable {
    public static let localID = "local"
    case local
    case provider(String)

    public var id: String {
        switch self {
        case .local: Self.localID
        case .provider(let id): id
        }
    }
}

/// Where a provider key lives. One Keychain service per provider, one account for the key.
/// The macOS store maps `itemClass` and `accessible` to `kSecClassGenericPassword` and
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
public enum ProviderCredentialLocation {
    public static let account = "api-key"
    public static let itemClass = "generic-password"
    public static let accessible = "when-unlocked-this-device-only"

    public static func service(for providerID: String) -> String {
        let clean = providerID.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
        return "app.zeus.voice-provider.\(clean)"
    }
}

/// Shown when a key is refused. It names what to do next and never includes the key.
public enum VoiceProviderKeyCopy {
    public static let rejected = "Paste the key again. It needs 8 to 256 characters and no spaces or line breaks."
}

public enum VoiceProviderCopy {
    public static let onboarding = "Zeus speaks with the local voice on this Mac. Spoken words are sent to a provider only after you add it, validate it, and select it."
    public static let helper = "Spoken text leaves this Mac only while that provider is selected and ready. If it is not ready, Zeus speaks with the local voice for that turn."
    public static let maskingNote = "The key stays in the Keychain on this Mac. It is hidden here, and it is not written into logs or settings."
    public static let sample = "This is Zeus."
}

/// Voice-leg and first-audio ceilings. `voiceLegMs` is the existing Settings test-button budget
/// (`VoiceLatencyTargets.voiceLegMs` in VoiceLatencyTrace.swift). `firstAudioP50Ms` is the on-device
/// first-audio p50 in the companion parity budgets. `directStreamP95Ms` is that spec's direct-stream p95.
/// This path does not change the existing 20 s and 45 s request ceilings.
public enum ProviderLatencyVerdict {
    public static let voiceLegMs = 600
    public static let firstAudioP50Ms = 700
    public static let directStreamP95Ms = 1_400

    public static func meetsVoiceLeg(_ milliseconds: Int) -> Bool { milliseconds <= voiceLegMs }
    public static func meetsFirstAudioP50(_ milliseconds: Int) -> Bool { milliseconds <= firstAudioP50Ms }
    public static func meetsDirectStreamP95(_ milliseconds: Int) -> Bool { milliseconds <= directStreamP95Ms }
}

public enum ProviderHTTPBudget {
    /// Provider calls only. The 20 s and 45 s ceilings elsewhere stay as they are.
    public static let requestTimeout: TimeInterval = 8
}
