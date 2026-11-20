import Foundation

/// Local voice switches. Both stay off until a person turns one on. Nothing here loads a model.
public struct LocalVoiceFlags: Codable, Sendable, Equatable {
    public var conversationMode: Bool
    public var pocketTTS: Bool

    public init(conversationMode: Bool = false, pocketTTS: Bool = false) {
        self.conversationMode = conversationMode
        self.pocketTTS = pocketTTS
    }
}
