import Foundation

/// Every engine that can speak, in the order `auto` prefers them.
public enum UltronEngine: String, CaseIterable, Sendable {
    case elevenLabs, openAI, kokoro, chatterbox, system

    public var label: String {
        switch self {
        case .elevenLabs: "ElevenLabs"
        case .openAI: "OpenAI voice"
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
    public var kokoroReady: Bool
    public var kokoroPaused: Bool
    public var chatterboxReady: Bool
    public var chatterboxPaused: Bool

    public init(elevenLabsConfigured: Bool = false, elevenLabsPaused: Bool = false,
                openAIConfigured: Bool = false, openAIPaused: Bool = false,
                kokoroReady: Bool = false, kokoroPaused: Bool = false,
                chatterboxReady: Bool = false, chatterboxPaused: Bool = false) {
        self.elevenLabsConfigured = elevenLabsConfigured
        self.elevenLabsPaused = elevenLabsPaused
        self.openAIConfigured = openAIConfigured
        self.openAIPaused = openAIPaused
        self.kokoroReady = kokoroReady
        self.kokoroPaused = kokoroPaused
        self.chatterboxReady = chatterboxReady
        self.chatterboxPaused = chatterboxPaused
    }

    /// Nil when usable, else the plain reason it is skipped.
    public func skipReason(_ engine: UltronEngine) -> String? {
        switch engine {
        case .elevenLabs: !elevenLabsConfigured ? "no ElevenLabs key or worker" : (elevenLabsPaused ? "ElevenLabs paused after a failure" : nil)
        case .openAI: !openAIConfigured ? "no OpenAI key" : (openAIPaused ? "OpenAI paused after a failure" : nil)
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
    /// Auto order: lowest-latency designed voice first. A cloud engine whose recent first-audio time
    /// is over `slowMs` drops behind the others, so a working but slow engine does not lead.
    /// Chatterbox clones from a reference clip the owner supplies, so it is used only when chosen explicitly.
    public static let autoOrder: [UltronEngine] = [.elevenLabs, .openAI, .kokoro, .system]
    public static let slowMs = 2_500

    public static func chain(choice: UltronEngineChoice, availability: UltronEngineAvailability,
                             observedFirstAudioMs: [UltronEngine: Int] = [:]) -> [UltronRouteDecision] {
        var decisions: [UltronRouteDecision] = []
        var seen = Set<UltronEngine>()
        func add(_ engine: UltronEngine, _ reason: String) {
            guard seen.insert(engine).inserted else { return }
            decisions.append(UltronRouteDecision(engine: engine, reason: reason))
        }
        var skipped: [String] = []
        if case .fixed(let chosen) = choice {
            if let why = availability.skipReason(chosen) {
                skipped.append("\(chosen.label) chosen but \(why)")
            } else {
                add(chosen, "chosen in Settings")
            }
        }
        let usable = autoOrder.filter { availability.skipReason($0) == nil }
        let fast = usable.filter { (observedFirstAudioMs[$0] ?? 0) <= slowMs }
        let slow = usable.filter { (observedFirstAudioMs[$0] ?? 0) > slowMs }
        for engine in fast + slow {
            if engine == .system { continue }
            let tail = slow.contains(engine) ? "usable but slow lately" : "best available, lowest latency"
            add(engine, (skipped.first.map { "\($0); " } ?? "auto: ") + tail)
        }
        let first = decisions.isEmpty
        let why = first
            ? "no cloud or local voice is ready (" + (skipped + autoOrder.compactMap { $0 == .system ? nil : availability.skipReason($0) }).prefix(2).joined(separator: ", ") + "); the deepest Mac voice with the Ultron effect"
            : "last resort"
        add(.system, why)
        return decisions
    }
}
