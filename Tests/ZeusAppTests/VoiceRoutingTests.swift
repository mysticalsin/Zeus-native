import Testing
@testable import Zeus

/// QA7 round 12: `zeus status`, the Settings > Voice card and `voice.log` disagreed about which
/// engine was about to speak, because `Speaker.engineDescription` was a separate, older guess.
/// `VoiceRouting.resolve` is now the one pure decision both call sites use; these tests cover it
/// without touching AVFoundation, the Keychain or any singleton.
@Suite("Voice routing resolves one truth for every engine/pause combination")
struct VoiceRoutingTests {
    @Test func kokoroChosenAndReadyWinsOverEverythingElse() {
        #expect(VoiceRouting.resolve(engine: .kokoro, kokoroReady: true, hasElevenLabsRoute: true, elevenLabsPaused: false) == .kokoro)
    }

    @Test func systemChosenAlwaysWinsRegardlessOfElevenLabs() {
        #expect(VoiceRouting.resolve(engine: .system, kokoroReady: true, hasElevenLabsRoute: true, elevenLabsPaused: false) == .system)
    }

    @Test func elevenLabsChosenAndAvailableAndNotPausedWins() {
        #expect(VoiceRouting.resolve(engine: .elevenLabs, kokoroReady: true, hasElevenLabsRoute: true, elevenLabsPaused: false) == .elevenLabs)
    }

    @Test func elevenLabsChosenButPausedFallsToKokoroWhenReady() {
        #expect(VoiceRouting.resolve(engine: .elevenLabs, kokoroReady: true, hasElevenLabsRoute: true, elevenLabsPaused: true) == .kokoro)
    }

    @Test func elevenLabsChosenButPausedAndKokoroNotReadyFallsToSystem() {
        #expect(VoiceRouting.resolve(engine: .elevenLabs, kokoroReady: false, hasElevenLabsRoute: true, elevenLabsPaused: true) == .system)
    }

    @Test func elevenLabsChosenButNoRouteAtAllFallsToKokoroThenSystem() {
        #expect(VoiceRouting.resolve(engine: .elevenLabs, kokoroReady: true, hasElevenLabsRoute: false, elevenLabsPaused: false) == .kokoro)
        #expect(VoiceRouting.resolve(engine: .elevenLabs, kokoroReady: false, hasElevenLabsRoute: false, elevenLabsPaused: false) == .system)
    }

    /// Kokoro chosen but not actually set up yet (e.g. mid first-run download) falls through to
    /// ElevenLabs if one is configured, matching the pre-existing fallback order -- not a silent
    /// system-voice downgrade while a perfectly good cloud voice is available.
    @Test func kokoroChosenButNotReadyFallsToElevenLabsWhenAvailable() {
        #expect(VoiceRouting.resolve(engine: .kokoro, kokoroReady: false, hasElevenLabsRoute: true, elevenLabsPaused: false) == .elevenLabs)
    }

    @Test func kokoroChosenButNotReadyAndNoElevenLabsFallsToSystem() {
        #expect(VoiceRouting.resolve(engine: .kokoro, kokoroReady: false, hasElevenLabsRoute: false, elevenLabsPaused: false) == .system)
    }
}
