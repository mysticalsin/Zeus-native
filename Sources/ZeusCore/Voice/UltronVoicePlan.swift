import Foundation

/// The Ultron voice preset.
/// A 401 is not a voice the person should hear. Preview stays silent unless AUDIBLE-OK is set.
public enum UltronVoicePlan {
    public static let presetTitle = "Ultron voice (default)"

    public enum Engine: String, Equatable, Sendable {
        case kokoro
        case elevenLabs
        case system
    }

    /// Default order is the local voice. A cloud key does not change it.
    public static func preferred(kokoroReady: Bool, elevenLabsKeyValid: Bool) -> Engine {
        _ = elevenLabsKeyValid
        return kokoroReady ? .kokoro : .system
    }

    /// The engine a launch starts on. Only an explicit owner pick (`voice.engine.userSelected`) beats the
    /// local default. A saved key is not a pick.
    public static func initialEngine(stored: Engine?, userSelected: Bool, kokoroReady: Bool, elevenLabsKeyValid: Bool) -> Engine {
        if let stored, userSelected { return stored }
        return preferred(kokoroReady: kokoroReady, elevenLabsKeyValid: elevenLabsKeyValid)
    }

    /// The provider shown in Settings when the owner never picked one. A key does not select a cloud voice.
    public static func defaultProvider(kokoroReady: Bool, elevenLabsKeyValid: Bool) -> VoiceTTSProvider {
        _ = kokoroReady
        _ = elevenLabsKeyValid
        return .kokoro
    }

    /// How long ElevenLabs stays out of the chain after a failed request: a bad key or empty credits
    /// (401, 402) for 15 minutes; a network error or timeout (nil status), a rate limit or a server error
    /// for 60 seconds, so the rest of that reply and the next few go straight to Kokoro.
    public static func pauseSeconds(status: Int?) -> TimeInterval {
        (status == 401 || status == 402) ? 15 * 60 : 60
    }

    /// A stored pause only counts until its time passes, so ElevenLabs is tried again after credits reset.
    public static func isPaused(until: Date?, now: Date) -> Bool {
        guard let until else { return false }
        return until > now
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
