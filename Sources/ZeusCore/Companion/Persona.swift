import Foundation

/// A switchable companion personality. Classic is the default and adds nothing to Zeus's prompt.
/// The addendum is applied only when an LLM system prompt is built. Face unlock and instant
/// commands do not read it.
public protocol Persona: Sendable {
    var id: String { get }
    var displayName: String { get }
    var systemPromptAddendum: String { get }
    var mascotKind: MascotKind { get }
    var voicePreference: PersonaVoicePreference { get }
}

public enum MascotKind: String, Sendable, Equatable {
    case classic
    case orb
}

public enum PersonaVoicePreference: String, Sendable, Equatable {
    /// Zeus's existing voice stack. This is the default for every persona.
    case zeusDefault
    /// Consulted only by `JarvisCloudVoice`. Off, or on without a configured id, keeps the existing stack.
    case jarvisCloudWhenConfigured
}

public enum ResolvedVoice: Sendable, Equatable {
    case zeusDefault
    case cloud(id: String)
}

public enum CompanionPromptOverlay {
    /// Classic returns `prompt` unchanged. Any other persona appends its addendum after a blank line.
    public static func applying(persona: any Persona, to prompt: String) -> String {
        let addendum = persona.systemPromptAddendum
        if addendum.isEmpty { return prompt }
        return prompt + "\n\n" + addendum
    }
}

public enum PersonaCatalog {
    public static let defaultsKey = "companion.persona"

    public static func persona(id: String) -> any Persona {
        if id == OrbPersona.id { return OrbPersona() }
        return MascotPersona()
    }

    public static func current(_ defaults: UserDefaults = .standard) -> any Persona {
        persona(id: defaults.string(forKey: defaultsKey) ?? "")
    }

    public static func select(id: String, defaults: UserDefaults = .standard) {
        defaults.set(persona(id: id).id, forKey: defaultsKey)
    }
}

/// The third-party cloud voice id is inert unless this flag is on and an id was configured
/// outside the repo. There is no key in source. An unconfigured flag falls back to Zeus's voice stack.
public enum JarvisCloudVoice {
    public static let enabledKey = "companion.jarvisCloudVoice.enabled"
    public static let configurationKey = "companion.jarvisCloudVoice.id"
    public static let cloudVoiceID = "JARVIS (MCU)"

    public static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? false
    }

    public static func selectedID(_ defaults: UserDefaults = .standard) -> String? {
        guard isEnabled(defaults) else { return nil }
        guard defaults.string(forKey: configurationKey) == cloudVoiceID else { return nil }
        return cloudVoiceID
    }
}

public enum PersonaVoiceResolver {
    public static func resolve(_ persona: any Persona, defaults: UserDefaults = .standard) -> ResolvedVoice {
        guard persona.voicePreference == .jarvisCloudWhenConfigured else { return .zeusDefault }
        guard let id = JarvisCloudVoice.selectedID(defaults) else { return .zeusDefault }
        return .cloud(id: id)
    }
}

/// What the persona is allowed to change. Local controls stay on the existing lines.
public enum PersonaScope {
    public static let affectsFaceUnlock = false
    public static let affectsInstantCommands = false
    public static let affectsLLMSystemPrompt = true
}

public enum OrbVisualState: String, Sendable, Equatable, CaseIterable {
    case idle, listening, thinking, speaking, compacting
}

public enum OrbVisualStateMap {
    /// TODO: bind this to CompanionTurnPhase once S1 merges.
    /// S1 owns Sources/ZeusCore/Companion/CompanionTurnMachine.swift and CompanionTurnPhase.swift.
    /// This slice does not create those types. `error` is not a state in frontend/src/orb.ts:16,
    /// so it stays idle until that binding can name a real phase.
    public static func visualState(forPhaseName name: String) -> OrbVisualState {
        switch name {
        case "listening": .listening
        case "transcribing", "thinking": .thinking
        case "speaking": .speaking
        case "compacting": .compacting
        default: .idle
        }
    }
}

/// Native pixels, frame pacing and CPU are not claimed from this process.
public enum OrbMacProof {
    public static let status = "MAC-PENDING"
    public static let linuxNote = "Linux has no Metal. This module does not render."
    public static let budgets = "0 dropped frames at 60 Hz and at 120 Hz, and under 5% of one core while animating on Apple Silicon."
    public static let artifacts = ["idle.png", "listening.png", "thinking.png", "speaking.png", "compacting.png", "frame-times.csv"]
}
