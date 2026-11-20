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
    case rateLimited
    case server(Int)
    case timedOut
    case cancelled
    case invalidResponse
    case notHTTPS
    case missingCredential
    case notRegistered

    public var logName: String {
        switch self {
        case .unauthorized: "unauthorized"
        case .rateLimited: "rate-limited"
        case .server(let status): "server-\(status)"
        case .timedOut: "timed-out"
        case .cancelled: "cancelled"
        case .invalidResponse: "invalid-response"
        case .notHTTPS: "not-https"
        case .missingCredential: "missing-credential"
        case .notRegistered: "not-registered"
        }
    }

    public var pill: String {
        switch self {
        case .unauthorized: "Key rejected"
        case .rateLimited: "Rate limited"
        case .server: "Provider unavailable"
        case .timedOut: "Timed out"
        case .cancelled: "Cancelled"
        case .invalidResponse: "No audio"
        case .notHTTPS: "Blocked"
        case .missingCredential: "Needs a key"
        case .notRegistered: "Unavailable"
        }
    }

    /// Maps a status code. A 400 counts as a rejected key only while validating, because a synthesize
    /// call can return 400 for a bad voice name.
    public static func fromHTTPStatus(_ status: Int, validating: Bool = false) -> ProviderFailure {
        switch status {
        case 401, 403: .unauthorized
        case 400 where validating: .unauthorized
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
        return .invalidResponse
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

public enum VoiceProviderCopy {
    public static let onboarding = "Zeus speaks with the local voice on this Mac. Spoken words are sent to a provider only after you add it, validate it, and select it."
    public static let helper = "Spoken text leaves this Mac only while that provider is selected and ready. If it is not ready, Zeus speaks with the local voice for that turn."
    public static let maskingNote = "The key stays in the Keychain on this Mac. It is hidden here, and it is not written into logs or settings."
    public static let sample = "This is Zeus."
}

/// Voice-leg and direct-stream ceilings. `voiceLegMs` is the existing Settings test-button budget
/// (`VoiceLatencyTargets.voiceLegMs` in VoiceLatencyTrace.swift). The 900 ms and 1,400 ms figures are
/// the direct-stream p50 and p95 in specs/007-companion-parity/perf-budgets.md. This path does not
/// change the existing 20 s and 45 s request ceilings.
public enum ProviderLatencyVerdict {
    public static let voiceLegMs = 600
    public static let directStreamP50Ms = 900
    public static let directStreamP95Ms = 1_400

    public static func meetsVoiceLeg(_ milliseconds: Int) -> Bool { milliseconds <= voiceLegMs }
    public static func meetsDirectStreamP95(_ milliseconds: Int) -> Bool { milliseconds <= directStreamP95Ms }
}

public enum ProviderHTTPBudget {
    /// Provider calls only. The 20 s and 45 s ceilings elsewhere stay as they are.
    public static let requestTimeout: TimeInterval = 8
}
