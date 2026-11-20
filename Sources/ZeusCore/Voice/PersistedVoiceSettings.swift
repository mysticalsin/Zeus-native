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

    /// Placeholder. The stored engine is not read yet, so a saved choice comes back as the Mac voice.
    public func resolvedEngine(kokoroReady: Bool, elevenLabsKeyValid: Bool) -> UltronVoicePlan.Engine {
        _ = (kokoroReady, elevenLabsKeyValid, engine, userSelected)
        return .system
    }

    public func resolvedProvider(kokoroReady: Bool, elevenLabsKeyValid: Bool) -> VoiceTTSProvider {
        _ = (kokoroReady, elevenLabsKeyValid, ttsProvider)
        return .kokoro
    }

    public func resolvedEngineAuto() -> Bool {
        _ = engineAuto
        return false
    }
}
