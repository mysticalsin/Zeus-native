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
    /// Zeus's local voice, with the existing AVSpeechSynthesizer fallback.
    case zeusDefault
}

/// Original synthetic voice. Not a third-party preset and not a film character.
public enum PersonaSyntheticVoice {
    public static let voiceID = "zeus.synthetic"
}

public enum ResolvedVoice: Sendable, Equatable {
    case zeusDefault

    /// The only voice id a persona can resolve.
    public var voiceID: String { PersonaSyntheticVoice.voiceID }
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

public enum PersonaVoiceResolver {
    /// Every persona resolves to the original synthetic voice. A leftover third-party
    /// voice flag, including one that is on and stores a character id, is ignored.
    public static func resolve(_ persona: any Persona, defaults: UserDefaults = .standard) -> ResolvedVoice {
        switch persona.voicePreference {
        case .zeusDefault:
            _ = defaults
            return .zeusDefault
        }
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
