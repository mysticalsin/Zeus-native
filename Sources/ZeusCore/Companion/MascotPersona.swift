import Foundation

/// The current mascot and the current prompt. `systemPromptAddendum` is empty, so the overlay
/// leaves a prompt byte-identical.
public struct MascotPersona: Persona, Sendable {
    public static let id = "classic"
    public static let displayName = "Classic"

    public init() {}

    public var id: String { Self.id }
    public var displayName: String { Self.displayName }
    public var systemPromptAddendum: String { "" }
    public var mascotKind: MascotKind { .classic }
    public var voicePreference: PersonaVoicePreference { .zeusDefault }
}
