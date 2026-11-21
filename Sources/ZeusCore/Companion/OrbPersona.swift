import Foundation

/// Optional particle mascot and spoken-reply personality. Off until the persona setting selects it.
public struct OrbPersona: Persona, Sendable {
    public static let id = "orb.jarvis"
    public static let displayName = "Orb (Jarvis)"

    public init() {}

    public var id: String { Self.id }
    public var displayName: String { Self.displayName }
    public var systemPromptAddendum: String { JarvisPersona.addendum }
    public var mascotKind: MascotKind { .orb }
    /// Original synthetic voice. Zeus's local voice, with the existing AVSpeechSynthesizer fallback.
    public var voicePreference: PersonaVoicePreference { .zeusDefault }
}
