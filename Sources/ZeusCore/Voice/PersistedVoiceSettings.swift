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
        userSelected = try container.decodeIfPresent(Bool.self, forKey: .userSelected) ?? false
        ttsProvider = try container.decodeIfPresent(String.self, forKey: .ttsProvider)
        engineAuto = try container.decodeIfPresent(Bool.self, forKey: .engineAuto)
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
