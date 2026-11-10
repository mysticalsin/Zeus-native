import Foundation

/// Log-safe key presence checks for TTS providers (K2). Never log key material.
public enum VoiceProviderKeychain {
    public static let service = "com.zeus.app"

    public static func logLine(present: Bool) -> String {
        present ? "key present" : "key missing"
    }

    public static func accounts(for provider: VoiceTTSProvider) -> [String] {
        switch provider {
        case .elevenLabs: ["elevenlabs.api-key"]
        case .chatterbox: ["chatterbox.api-key"]
        case .openAICompatible: ["openai-tts.api-key"]
        case .kokoro: []
        }
    }
}
