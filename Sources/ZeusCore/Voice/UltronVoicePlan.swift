import Foundation

/// The Ultron voice preset: a free local engine first, ElevenLabs only when its key is valid.
/// A 401 is not a voice the person should hear. Preview stays silent unless AUDIBLE-OK is set.
public enum UltronVoicePlan {
    public static let presetTitle = "Ultron voice (default)"

    public enum Engine: String, Equatable, Sendable {
        case kokoro
        case elevenLabs
        case system
    }

    /// Default order. Kokoro (on this Mac) wins whenever it is ready, even if an ElevenLabs key is saved.
    /// ElevenLabs is next, and only when that key has not been rejected. Otherwise the Mac voice.
    public static func preferred(kokoroReady: Bool, elevenLabsKeyValid: Bool) -> Engine {
        if kokoroReady { return .kokoro }
        if elevenLabsKeyValid { return .elevenLabs }
        return .system
    }

    /// 401 and 402 mean the key itself is bad. Speak with the local engine instead, and do not say an error aloud.
    /// Nil for any other status (the caller keeps its own retry or rate-limit pause).
    public static func afterRejection(status: Int, kokoroReady: Bool) -> Engine? {
        guard status == 401 || status == 402 else { return nil }
        return kokoroReady ? .kokoro : .system
    }

    /// One voice.log detail per spoken reply. Both words are required; the key is never included.
    public static func logLine(engine: String, voice: String) -> String {
        "engine=\(engine) voice=\(voice)"
    }

    public static func engineLabel(_ engine: Engine, kokoroVoice: String) -> String {
        switch engine {
        case .kokoro: "Kokoro \(kokoroVoice)"
        case .elevenLabs: "ElevenLabs"
        case .system: "Mac voice"
        }
    }

    /// Playback is allowed only when AUDIBLE-OK is a non-empty value other than "0".
    /// Absent (silent mode, every swarm lane) means Preview renders a file and does not play it.
    public static func previewPlaysAudio(audibleOK: String?) -> Bool {
        let value = audibleOK?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !value.isEmpty && value != "0" && value.lowercased() != "false"
    }
}
