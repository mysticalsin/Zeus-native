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
    /// The cloud id stays behind `JarvisCloudVoice`, which defaults off.
    public var voicePreference: PersonaVoicePreference { .jarvisCloudWhenConfigured }
}
