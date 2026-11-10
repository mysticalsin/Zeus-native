import Foundation

/// Which engine actually speaks the next line. Pure decision, no AVFoundation/Keychain I/O, so
/// it is directly unit-testable and shared by `Speaker.speak(_:)` and `Speaker.engineDescription`
/// -- QA7 round 12 ("Ultron voice by default" FAIL) found all three of `zeus status`, the
/// Settings > Voice card, and `voice.log` telling a different story about what was about to
/// play, because `engineDescription` was its own, older, disconnected guess (only "is there an
/// ElevenLabs route" plus a short-lived instance pause) instead of asking the same question
/// `speak(_:)` actually answers. One function now answers it for both call sites.
enum VoiceRoute: Equatable {
    case kokoro
    case system
    case elevenLabs
}

enum VoiceRouting {
    /// - `engine`: the stored/default `VoiceSettings.engine` choice.
    /// - `kokoroReady`: `KokoroVoice.isSetUp` right now.
    /// - `hasElevenLabsRoute`: `!ElevenLabsVoice.loadRoutes().isEmpty` (a direct key or a worker).
    /// - `elevenLabsPaused`: either the persisted `VoiceSettings.elevenLabsPausedUntil` or the
    ///   `Speaker` instance's own short pause, already resolved to a single "paused right now" bool.
    static func resolve(engine: VoiceEngine, kokoroReady: Bool, hasElevenLabsRoute: Bool,
                        elevenLabsPaused: Bool) -> VoiceRoute {
        if engine == .kokoro, kokoroReady { return .kokoro }
        if engine == .system { return .system }
        // engine == .elevenLabs, or .kokoro chosen but not actually set up yet -- try
        // ElevenLabs next (matches the pre-existing fallback order), then Kokoro, then System.
        if hasElevenLabsRoute, !elevenLabsPaused { return .elevenLabs }
        return kokoroReady ? .kokoro : .system
    }
}
