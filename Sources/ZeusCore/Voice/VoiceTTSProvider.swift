import Foundation

/// Cloud and local engines that can speak a reply, in the order shown in Settings > Voice (K1).
public enum VoiceTTSProvider: String, CaseIterable, Sendable, Identifiable {
    case kokoro
    case chatterbox
    case elevenLabs
    case openAICompatible

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .kokoro: "Local Kokoro"
        case .chatterbox: "Local Chatterbox Turbo"
        case .elevenLabs: "ElevenLabs"
        case .openAICompatible: "OpenAI-compatible TTS"
        }
    }

    /// Keychain account under service `com.zeus.app` (ElevenLabs keeps legacy `elevenlabs.api-key`).
    public var keychainAccount: String {
        switch self {
        case .elevenLabs: "elevenlabs.api-key"
        case .chatterbox: "chatterbox.api-key"
        case .openAICompatible: "openai-tts.api-key"
        case .kokoro: "kokoro.api-key"
        }
    }

    public var needsKey: Bool {
        switch self {
        case .kokoro, .chatterbox: false
        case .elevenLabs, .openAICompatible: true
        }
    }
}

public enum VoiceProviderStatus: Equatable, Sendable {
    case ready
    case needsKey
    case quotaOr401(String)
    case offline
    case notInstalled
    case pausedUntil(Date)

    public var label: String {
        switch self {
        case .ready: "Ready"
        case .needsKey: "Needs key"
        case .quotaOr401(let detail): detail
        case .offline: "Offline"
        case .notInstalled: "Not installed"
        case .pausedUntil: "Paused"
        }
    }
}

/// Which provider to try next after failures (K4). Pure logic for unit tests.
public enum VoiceProviderFallback {
    public struct Availability: Sendable {
        public var kokoroReady: Bool
        public var chatterboxReady: Bool
        public var elevenLabsConfigured: Bool
        public var openAIConfigured: Bool
        public var systemVoiceReady: Bool

        public init(kokoroReady: Bool, chatterboxReady: Bool, elevenLabsConfigured: Bool,
                    openAIConfigured: Bool, systemVoiceReady: Bool = true) {
            self.kokoroReady = kokoroReady
            self.chatterboxReady = chatterboxReady
            self.elevenLabsConfigured = elevenLabsConfigured
            self.openAIConfigured = openAIConfigured
            self.systemVoiceReady = systemVoiceReady
        }
    }

    /// Ordered candidates: chosen first, then the rest in K1 order, then Kokoro if not already included.
    public static func chain(chosen: VoiceTTSProvider, availability: Availability) -> [VoiceTTSProvider] {
        let k1: [VoiceTTSProvider] = [.kokoro, .chatterbox, .elevenLabs, .openAICompatible]
        var result: [VoiceTTSProvider] = []
        if isConfigured(chosen, availability: availability) { result.append(chosen) }
        for provider in k1 where provider != chosen && isConfigured(provider, availability: availability) {
            if !result.contains(provider) { result.append(provider) }
        }
        if availability.kokoroReady, !result.contains(.kokoro) { result.append(.kokoro) }
        return result
    }

    public static func isConfigured(_ provider: VoiceTTSProvider, availability: Availability) -> Bool {
        switch provider {
        case .kokoro: availability.kokoroReady
        case .chatterbox: availability.chatterboxReady
        case .elevenLabs: availability.elevenLabsConfigured
        case .openAICompatible: availability.openAIConfigured
        }
    }

    public static func next(after failure: VoiceTTSProvider, in chain: [VoiceTTSProvider]) -> VoiceTTSProvider? {
        guard let index = chain.firstIndex(of: failure), index + 1 < chain.count else { return nil }
        return chain[index + 1]
    }
}

/// Remembers providers that failed so they are not retried for ten minutes (K4).
public struct VoiceProviderPauseTracker: Sendable {
    private var pausedUntil: [VoiceTTSProvider: Date] = [:]
    public var cooldown: TimeInterval = 10 * 60

    public init() {}

    public mutating func noteFailure(_ provider: VoiceTTSProvider, now: Date = Date()) {
        pausedUntil[provider] = now.addingTimeInterval(cooldown)
    }

    public func isPaused(_ provider: VoiceTTSProvider, now: Date = Date()) -> Bool {
        guard let until = pausedUntil[provider] else { return false }
        return until > now
    }

    public mutating func clear(_ provider: VoiceTTSProvider) {
        pausedUntil.removeValue(forKey: provider)
    }
}
