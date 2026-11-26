import Foundation

/// Settings > Integrations > AI Connections.
///
/// The six kinds are the section. Providers register as plugs. ElevenLabs is the
/// built-in external voice and the only one `standard()` registers. A secret is
/// written only through `KeychainStore` (service `com.zeus.app`). Preferences
/// store the plug id, whether it is enabled, and the Keychain account name.
/// They have no field for key material, and this type does not open a network
/// connection.

public enum AIConnectionKind: String, CaseIterable, Sendable, Identifiable {
    case cloudProtocol
    case cli
    case cursor
    case elevenLabsAPI
    case modelAPI
    case voiceChat

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cloudProtocol: "Cloud Protocol"
        case .cli: "CLI"
        case .cursor: "Cursor"
        case .elevenLabsAPI: "ElevenLabs API"
        case .modelAPI: "Other model APIs"
        case .voiceChat: "Voice chat"
        }
    }

    /// Stable explanation. The status pill carries whether a key is saved.
    public var summary: String {
        switch self {
        case .cloudProtocol: "Direct connection for the cloud protocol."
        case .cli: "Direct connection for a command line provider."
        case .cursor: "Direct connection for Cursor."
        case .elevenLabsAPI: "External voice. The key stays in the Keychain."
        case .modelAPI: "Direct connection for another model API."
        case .voiceChat: "Spoken conversation with a registered voice."
        }
    }
}

public struct AIConnectionPlug: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var kind: AIConnectionKind
    /// Account under `KeychainStore.service`. Nil when the plug stores no secret.
    /// ElevenLabs uses the existing `elevenlabs.api-key` slot.
    public var keychainAccount: String?
    public var externalVoice: Bool

    public init(id: String, title: String, kind: AIConnectionKind, keychainAccount: String? = nil, externalVoice: Bool = false) {
        self.id = id
        self.title = title
        self.kind = kind
        self.keychainAccount = keychainAccount
        self.externalVoice = externalVoice
    }

    public static let elevenLabs = AIConnectionPlug(
        id: "elevenlabs.voice",
        title: "ElevenLabs",
        kind: .elevenLabsAPI,
        keychainAccount: "elevenlabs.api-key",
        externalVoice: true
    )
}

public enum AIConnectionRegisterResult: Equatable, Sendable {
    case added
    case duplicate
    case rejected
}

public struct AIConnectionSectionRow: Equatable, Sendable, Identifiable {
    public var kind: AIConnectionKind
    public var plugs: [AIConnectionPlug]
    public var id: String { kind.rawValue }
    public var secretPlugs: [AIConnectionPlug] { plugs.filter { $0.keychainAccount != nil } }
}

public struct AIConnectionStatus: Equatable, Sendable {
    public var label: String
    public var saved: Bool
    /// Log line. Either "key present" or "key missing", never the key.
    public var diagnostic: String
}

/// What may be written to UserDefaults for one plug. No key material.
public struct AIConnectionPreference: Codable, Equatable, Sendable {
    public var plugID: String
    public var enabled: Bool
    public var keychainAccount: String?

    public init(plugID: String, enabled: Bool, keychainAccount: String?) {
        self.plugID = plugID
        self.enabled = enabled
        self.keychainAccount = keychainAccount
    }

    private enum CodingKeys: String, CodingKey {
        case plugID, enabled, keychainAccount
    }
}

public struct AIConnectionRegistry: Equatable, Sendable {
    public private(set) var plugs: [AIConnectionPlug] = []

    public init() {}

    /// ElevenLabs first. Later plugs append, so it stays the first external voice.
    public static func standard() -> AIConnectionRegistry {
        var registry = AIConnectionRegistry()
        _ = registry.register(.elevenLabs)
        return registry
    }

    public var externalVoices: [AIConnectionPlug] { plugs.filter(\.externalVoice) }

    public func plug(id: String) -> AIConnectionPlug? { plugs.first { $0.id == id } }

    public func rows() -> [AIConnectionSectionRow] {
        AIConnectionKind.allCases.map { kind in
            AIConnectionSectionRow(kind: kind, plugs: plugs.filter { $0.kind == kind })
        }
    }

    public mutating func register(_ plug: AIConnectionPlug) -> AIConnectionRegisterResult {
        guard Self.accepts(plug) else { return .rejected }
        guard !plugs.contains(where: { $0.id == plug.id }) else { return .duplicate }
        plugs.append(plug)
        return .added
    }

    public func status(for kind: AIConnectionKind, store: KeychainStore) -> AIConnectionStatus {
        let matching = plugs.filter { $0.kind == kind }
        guard !matching.isEmpty else {
            return AIConnectionStatus(label: "No provider registered", saved: false, diagnostic: Self.diagnostic(saved: false))
        }
        let secretPlugs = matching.filter { $0.keychainAccount != nil }
        guard !secretPlugs.isEmpty else {
            return AIConnectionStatus(label: "No key stored", saved: false, diagnostic: Self.diagnostic(saved: false))
        }
        let saved = secretPlugs.contains { Self.secretSaved($0, store: store) }
        return AIConnectionStatus(
            label: saved ? "Key saved" : "No key yet",
            saved: saved,
            diagnostic: Self.diagnostic(saved: saved)
        )
    }

    public static func secretSaved(_ plug: AIConnectionPlug, store: KeychainStore) -> Bool {
        guard let account = plug.keychainAccount, let value = store.get(account) else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func diagnostic(saved: Bool) -> String { saved ? "key present" : "key missing" }

    private static let tokenCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    private static let titleCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._-")

    static func accepts(_ plug: AIConnectionPlug) -> Bool {
        guard isToken(plug.id), isTitle(plug.title) else { return false }
        if let account = plug.keychainAccount, !isToken(account) { return false }
        if plug.externalVoice && plug.keychainAccount == nil { return false }
        return true
    }

    private static func isToken(_ value: String) -> Bool {
        (1...80).contains(value.count) && value.allSatisfy { tokenCharacters.contains($0) }
    }

    private static func isTitle(_ value: String) -> Bool {
        (1...80).contains(value.count) && value.allSatisfy { titleCharacters.contains($0) }
    }
}

public enum AIConnectionSaveResult: Equatable, Sendable {
    case saved
    case empty
    case refused
}

public enum AIConnectionRemoveResult: Equatable, Sendable {
    case removed
    case refused
}

/// In-memory drafts plus the preference record. The draft is never encoded.
public struct AIConnectionSession {
    public static let preferencesKey = "ai.connections.records"

    public private(set) var registry: AIConnectionRegistry
    private var drafts: [String: String] = [:]
    private var preferences: [AIConnectionPreference]
    private let defaults: UserDefaults

    public init(registry: AIConnectionRegistry = .standard(), defaults: UserDefaults) {
        self.registry = registry
        self.defaults = defaults
        let stored = Self.decoded(defaults)
        preferences = registry.plugs.map { plug in
            let enabled = stored.first { $0.plugID == plug.id }?.enabled ?? false
            return AIConnectionPreference(plugID: plug.id, enabled: enabled, keychainAccount: plug.keychainAccount)
        }
        let clean = Self.data(preferences)
        let raw = defaults.data(forKey: Self.preferencesKey)
        if raw != clean, let clean { Self.store(clean, defaults: defaults) }
    }

    public var rows: [AIConnectionSectionRow] { registry.rows() }

    public func draft(for plugID: String) -> String { drafts[plugID] ?? "" }

    public func status(for kind: AIConnectionKind, store: KeychainStore) -> AIConnectionStatus {
        registry.status(for: kind, store: store)
    }

    public func secretSaved(_ plug: AIConnectionPlug, store: KeychainStore) -> Bool {
        AIConnectionRegistry.secretSaved(plug, store: store)
    }

    public mutating func setDraft(_ value: String, plugID: String) {
        guard registry.plug(id: plugID) != nil else { return }
        drafts[plugID] = value
    }

    @discardableResult
    public mutating func register(_ plug: AIConnectionPlug) -> AIConnectionRegisterResult {
        let result = registry.register(plug)
        guard result == .added else { return result }
        preferences.append(AIConnectionPreference(plugID: plug.id, enabled: false, keychainAccount: plug.keychainAccount))
        if let data = Self.data(preferences) { Self.store(data, defaults: defaults) }
        return result
    }

    /// Empty input does not remove a saved key. The secret is passed only to `KeychainStore.set`.
    @discardableResult
    public mutating func saveDraft(plugID: String, store: KeychainStore) -> AIConnectionSaveResult {
        guard let plug = registry.plug(id: plugID), let account = plug.keychainAccount else { return .refused }
        let secret = draft(for: plugID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { return .empty }
        guard store.set(secret, for: account) else { return .refused }
        drafts[plugID] = ""
        if let index = preferences.firstIndex(where: { $0.plugID == plugID }) {
            preferences[index].enabled = true
            preferences[index].keychainAccount = account
        }
        if let data = Self.data(preferences) { Self.store(data, defaults: defaults) }
        return .saved
    }

    @discardableResult
    public mutating func removeSecret(plugID: String, store: KeychainStore) -> AIConnectionRemoveResult {
        guard let plug = registry.plug(id: plugID), let account = plug.keychainAccount else { return .refused }
        guard store.remove(account) else { return .refused }
        drafts[plugID] = ""
        if let index = preferences.firstIndex(where: { $0.plugID == plugID }) {
            preferences[index].enabled = false
            preferences[index].keychainAccount = account
        }
        if let data = Self.data(preferences) { Self.store(data, defaults: defaults) }
        return .removed
    }

    public func preferencesData() -> Data? { Self.data(preferences) }

    private static func decoded(_ defaults: UserDefaults) -> [AIConnectionPreference] {
        guard let data = defaults.data(forKey: preferencesKey) else { return [] }
        return (try? JSONDecoder().decode([AIConnectionPreference].self, from: data)) ?? []
    }

    private static func data(_ preferences: [AIConnectionPreference]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(preferences)
    }

    private static func store(_ data: Data, defaults: UserDefaults) {
        defaults.set(data, forKey: preferencesKey)
    }
}
