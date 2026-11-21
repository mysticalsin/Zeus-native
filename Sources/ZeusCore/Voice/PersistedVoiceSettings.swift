import Foundation

/// The voice keys an existing install already stores. New local-voice flags are not part of this record.
public struct PersistedVoiceSettings: Codable, Equatable, Sendable {
    public var engine: String?
    public var userSelected: Bool
    public var ttsProvider: String?
    public var engineAuto: Bool?

    enum CodingKeys: String, CodingKey {
        case engine = "voice.engine"
        case userSelected = "voice.engine.userSelected"
        case ttsProvider = "voice.ttsProvider"
        case engineAuto = "voice.engine.auto"
    }

    public init(engine: String? = nil, userSelected: Bool = false, ttsProvider: String? = nil, engineAuto: Bool? = nil) {
        self.engine = engine
        self.userSelected = userSelected
        self.ttsProvider = ttsProvider
        self.engineAuto = engineAuto
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        engine = try container.decodeIfPresent(String.self, forKey: .engine)
        userSelected = Self.flexibleBool(container, .userSelected) ?? false
        ttsProvider = try container.decodeIfPresent(String.self, forKey: .ttsProvider)
        engineAuto = Self.flexibleBool(container, .engineAuto)
    }

    /// The four keys `VoiceSettings` already writes. A string or number does not drop the engine.
    public static func load(_ defaults: UserDefaults) -> PersistedVoiceSettings {
        PersistedVoiceSettings(
            engine: defaults.string(forKey: "voice.engine"),
            userSelected: flexibleStoredBool(defaults, "voice.engine.userSelected") ?? false,
            ttsProvider: defaults.string(forKey: "voice.ttsProvider"),
            engineAuto: flexibleStoredBool(defaults, "voice.engine.auto")
        )
    }

    private static func flexibleBool(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Bool? {
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) { return value }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) {
            if text == "true" || text == "1" { return true }
            if text == "false" || text == "0" { return false }
        }
        if let number = try? container.decodeIfPresent(Int.self, forKey: key) { return number != 0 }
        return nil
    }

    private static func flexibleStoredBool(_ defaults: UserDefaults, _ key: String) -> Bool? {
        if defaults.object(forKey: key) == nil { return nil }
        if let value = defaults.object(forKey: key) as? Bool { return value }
        if let text = defaults.string(forKey: key) {
            if text == "true" || text == "1" { return true }
            if text == "false" || text == "0" { return false }
        }
        if let number = defaults.object(forKey: key) as? NSNumber { return number.boolValue }
        return nil
    }

    /// The engine a launch already starts on. Local-voice flags are not an input.
    public func resolvedEngine(kokoroReady: Bool, elevenLabsKeyValid: Bool) -> UltronVoicePlan.Engine {
        UltronVoicePlan.initialEngine(
            stored: engine.flatMap(UltronVoicePlan.Engine.init(rawValue:)),
            userSelected: userSelected, kokoroReady: kokoroReady, elevenLabsKeyValid: elevenLabsKeyValid)
    }

    /// A stored provider wins. Otherwise the existing default is used.
    public func resolvedProvider(kokoroReady: Bool, elevenLabsKeyValid: Bool) -> VoiceTTSProvider {
        if let ttsProvider, let provider = VoiceTTSProvider(rawValue: ttsProvider) { return provider }
        return UltronVoicePlan.defaultProvider(kokoroReady: kokoroReady, elevenLabsKeyValid: elevenLabsKeyValid)
    }

    /// Automatic unless the owner already wrote `voice.engine.auto`.
    public func resolvedEngineAuto() -> Bool {
        ElevenLabsFailsafe.defaultEngineAuto(explicit: engineAuto, storedProvider: ttsProvider)
    }
}
