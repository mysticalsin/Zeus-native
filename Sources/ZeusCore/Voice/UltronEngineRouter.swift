import Foundation

/// Every engine that can speak, in the order `auto` prefers them.
public enum UltronEngine: String, CaseIterable, Sendable {
    case elevenLabs, openAI, gemini, kokoro, chatterbox, system

    public var label: String {
        switch self {
        case .elevenLabs: "ElevenLabs"
        case .openAI: "OpenAI voice"
        case .gemini: "Gemini voice"
        case .kokoro: "Kokoro"
        case .chatterbox: "Chatterbox"
        case .system: "Mac voice"
        }
    }

    /// The `engine=` word in voice.log.
    public var logName: String { rawValue.lowercased() }
}

/// What is usable right now. The system voice is always usable and is always last.
public struct UltronEngineAvailability: Equatable, Sendable {
    public var elevenLabsConfigured: Bool
    public var elevenLabsPaused: Bool
    public var openAIConfigured: Bool
    public var openAIPaused: Bool
    public var geminiConfigured: Bool
    public var geminiPaused: Bool
    public var kokoroReady: Bool
    public var kokoroPaused: Bool
    public var chatterboxReady: Bool
    public var chatterboxPaused: Bool
    /// OpenAI speech has shut down (`OpenAISpeechRetirement`): treated like a missing key, the saved choice is kept.
    public var openAIRetired: Bool

    public init(elevenLabsConfigured: Bool = false, elevenLabsPaused: Bool = false,
                openAIConfigured: Bool = false, openAIPaused: Bool = false,
                geminiConfigured: Bool = false, geminiPaused: Bool = false,
                kokoroReady: Bool = false, kokoroPaused: Bool = false,
                chatterboxReady: Bool = false, chatterboxPaused: Bool = false,
                openAIRetired: Bool = false) {
        self.elevenLabsConfigured = elevenLabsConfigured
        self.elevenLabsPaused = elevenLabsPaused
        self.openAIConfigured = openAIConfigured
        self.openAIPaused = openAIPaused
        self.geminiConfigured = geminiConfigured
        self.geminiPaused = geminiPaused
        self.kokoroReady = kokoroReady
        self.kokoroPaused = kokoroPaused
        self.chatterboxReady = chatterboxReady
        self.chatterboxPaused = chatterboxPaused
        self.openAIRetired = openAIRetired
    }

    /// Nil when usable, else the plain reason it is skipped.
    public func skipReason(_ engine: UltronEngine) -> String? {
        switch engine {
        case .elevenLabs: !elevenLabsConfigured ? "no ElevenLabs key or worker" : (elevenLabsPaused ? "ElevenLabs paused after a failure" : nil)
        case .openAI: openAIRetired ? "OpenAI voices ended January 6, 2027" : !openAIConfigured ? "no OpenAI key" : (openAIPaused ? "OpenAI paused after a failure" : nil)
        case .gemini: !geminiConfigured ? "no Gemini key" : (geminiPaused ? "Gemini paused after a failure" : nil)
        case .kokoro: !kokoroReady ? "Kokoro not set up" : (kokoroPaused ? "Kokoro paused after a failure" : nil)
        case .chatterbox: !chatterboxReady ? "Chatterbox not ready" : (chatterboxPaused ? "Chatterbox paused after a failure" : nil)
        case .system: nil
        }
    }
}

/// `auto` (the default) or one engine the owner picked in Settings.
public enum UltronEngineChoice: Equatable, Sendable {
    case auto
    case fixed(UltronEngine)
}

public struct UltronRouteDecision: Equatable, Sendable {
    public var engine: UltronEngine
    /// One plain sentence for voice.log and the self-test receipt. Never holds a key.
    public var reason: String
}

/// Pure engine choice: no Keychain, no network. `Speaker` walks the chain until one speaks.
public enum UltronEngineRouter {
    /// Automatic order is the local voice, then the Mac voice. A saved cloud key does not join this list.
    /// Chatterbox is used only when the owner picks it.
    public static let autoOrder: [UltronEngine] = [.kokoro, .system]
    public static let slowMs = 2_500

    public static func chain(choice: UltronEngineChoice, availability: UltronEngineAvailability,
                             observedFirstAudioMs: [UltronEngine: Int] = [:]) -> [UltronRouteDecision] {
        _ = observedFirstAudioMs
        switch choice {
        case .auto:
            return local(availability, note: availability.skipReason(.kokoro) == nil
                ? "auto: zeus.synthetic local voice"
                : "auto: zeus.synthetic; no cloud or local voice is ready; the deepest Mac voice with the Ultron effect")
        case .fixed(let engine):
            if engine == .system {
                return [UltronRouteDecision(engine: .system, reason: "chosen in Settings")]
            }
            if isCloud(engine) {
                if let why = availability.skipReason(engine) {
                    return local(availability, note: "\(engine.label) chosen but \(why); zeus.synthetic")
                }
                return [UltronRouteDecision(engine: engine, reason: "chosen in Settings")]
                    + local(availability, note: "local fallback after \(engine.label)")
            }
            if engine == .chatterbox {
                if let why = availability.skipReason(.chatterbox) {
                    return local(availability, note: "Chatterbox chosen but \(why); zeus.synthetic")
                }
                return [UltronRouteDecision(engine: .chatterbox, reason: "chosen in Settings")]
                    + local(availability, note: "local fallback")
            }
            if availability.skipReason(.kokoro) == nil {
                return [UltronRouteDecision(engine: .kokoro, reason: "chosen in Settings"),
                        UltronRouteDecision(engine: .system, reason: "Mac voice offline fallback")]
            }
            return local(availability, note: "Kokoro chosen but \(availability.skipReason(.kokoro) ?? "not set up"); zeus.synthetic")
        }
    }

    private static func isCloud(_ engine: UltronEngine) -> Bool {
        switch engine {
        case .elevenLabs, .openAI, .gemini: true
        case .kokoro, .chatterbox, .system: false
        }
    }

    /// Kokoro when it is ready, then the Mac voice. No second cloud.
    private static func local(_ availability: UltronEngineAvailability, note: String) -> [UltronRouteDecision] {
        if availability.skipReason(.kokoro) == nil {
            return [UltronRouteDecision(engine: .kokoro, reason: note),
                    UltronRouteDecision(engine: .system, reason: "Mac voice offline fallback")]
        }
        return [UltronRouteDecision(engine: .system, reason: note)]
    }
}
