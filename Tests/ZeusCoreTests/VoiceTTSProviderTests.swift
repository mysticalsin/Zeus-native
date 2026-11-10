import Foundation
import Testing
@testable import ZeusCore

@Suite struct VoiceTTSProviderTests {
    @Test func fallbackChainStartsWithChosenThenK1Order() {
        let availability = VoiceProviderFallback.Availability(
            kokoroReady: true, chatterboxReady: true, elevenLabsConfigured: true, openAIConfigured: true)
        let chain = VoiceProviderFallback.chain(chosen: .elevenLabs, availability: availability)
        #expect(chain.first == .elevenLabs)
        #expect(chain.contains(.kokoro))
        #expect(chain.contains(.chatterbox))
    }

    @Test func chainSkipsPausedProviders() {
        let availability = VoiceProviderFallback.Availability(
            kokoroReady: true, chatterboxReady: true, elevenLabsConfigured: true, openAIConfigured: true)
        let chain = VoiceTTSChain.providers(chosen: .elevenLabs, availability: availability) { provider in
            provider == .elevenLabs
        }
        #expect(!chain.contains(.elevenLabs))
        #expect(chain.first == .kokoro || chain.first == .chatterbox)
    }

    @Test func firstAudioTimeoutIsFourSeconds() {
        #expect(VoiceTTSChain.firstAudioTimeout == 4)
    }

    @Test func missingModelSkipsChatterbox() {
        let availability = VoiceProviderFallback.Availability(
            kokoroReady: true, chatterboxReady: false, elevenLabsConfigured: false, openAIConfigured: false)
        #expect(VoiceProviderFallback.chain(chosen: .chatterbox, availability: availability) == [.kokoro])
    }

    @Test func pauseTrackerBlocksRetryForTenMinutes() {
        var tracker = VoiceProviderPauseTracker()
        let now = Date(timeIntervalSince1970: 1_000_000)
        tracker.noteFailure(.elevenLabs, now: now)
        #expect(tracker.isPaused(.elevenLabs, now: now.addingTimeInterval(9 * 60)))
        #expect(!tracker.isPaused(.elevenLabs, now: now.addingTimeInterval(11 * 60)))
    }

    @Test func keyLogLinesNeverMentionSecrets() {
        #expect(VoiceProviderKeychain.logLine(present: true) == "key present")
        #expect(VoiceProviderKeychain.logLine(present: false) == "key missing")
        #expect(!VoiceProviderKeychain.logLine(present: true).contains("sk-"))
    }

    @Test func ttsKeyRoundTripInKeychain() {
        let backend = MemoryKeychain()
        let store = KeychainStore(backend: backend, defaults: UserDefaults(suiteName: "zeus.tts.\(UUID())")!)
        store.set("secret-value", for: VoiceTTSProvider.openAICompatible.keychainAccount)
        #expect(store.has(VoiceTTSProvider.openAICompatible.keychainAccount))
        store.remove(VoiceTTSProvider.openAICompatible.keychainAccount)
        #expect(!store.has(VoiceTTSProvider.openAICompatible.keychainAccount))
    }
}

@Suite struct OpenAITTSRequestTests {
    @Test func buildsSpeechURLAndBody() throws {
        let base = URL(string: "https://api.openai.com/v1")!
        let config = OpenAITTSRequest.Config(baseURL: base, model: "tts-1", voice: "alloy", apiKey: "secret")
        #expect(OpenAITTSRequest.speechURL(base: base).absoluteString.hasSuffix("/v1/audio/speech"))
        let body = OpenAITTSRequest.body(text: "Hi", config: config)
        #expect(body["model"] as? String == "tts-1")
        #expect(body["voice"] as? String == "alloy")
        let request = OpenAITTSRequest.makeRequest(text: "Hi", config: config)
        #expect(request?.httpMethod == "POST")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }
}

@Suite struct QuietHoursVoiceTestTests {
    @Test func silentEnvForcesFileOnly() {
        #expect(QuietHoursVoiceTest.shouldWriteToFileOnly(now: Date(), env: ["ZEUS_SILENT_TESTS": "1"]))
    }

    @Test func lateEveningBRTIsQuiet() throws {
        var cal = QuietHoursVoiceTest.brtCalendar()
        var parts = DateComponents(calendar: cal, timeZone: cal.timeZone, year: 2026, month: 11, day: 3, hour: 22, minute: 0)
        let night = try #require(cal.date(from: parts))
        #expect(QuietHoursVoiceTest.shouldWriteToFileOnly(now: night, env: [:], calendar: cal))
    }
}

@Suite struct AudioQuietTests {
    @Test func muteGuardIsNoOpAtVolumeZero() {
        #expect(AudioQuiet.isMuteGuardActive(volume: 0, muted: false))
        #expect(AudioQuiet.duckTarget(snapshotVolume: 0, snapshotMuted: false) == nil)
    }

    @Test func muteGuardIsNoOpWhileMuted() {
        #expect(AudioQuiet.isMuteGuardActive(volume: 0.5, muted: true))
        #expect(AudioQuiet.duckTarget(snapshotVolume: 0.5, snapshotMuted: true) == nil)
    }

    @Test func duckOnlyLowersNeverRaises() {
        var quiet = AudioQuiet(snapshotVolume: 0.8, snapshotMuted: false)
        let target = quiet.beginDuck(fraction: 0.5)
        #expect(target == 0.4)
        #expect(quiet.restoreVolume(currentVolume: 0.4, currentMuted: false) == 0.8)
    }

    @Test func restoreNeverUnmutes() {
        var quiet = AudioQuiet(snapshotVolume: 0.5, snapshotMuted: true)
        #expect(quiet.beginDuck() == nil)
        #expect(quiet.restoreVolume(currentVolume: 0, currentMuted: true) == nil)
    }
}

@Suite struct PartialActionGateTests {
    @Test func revisedPartialBlocksAction() {
        var gate = PartialActionGate()
        gate.observePartial("open slack")
        var allowed = gate.mayActOnPartial("open slack")
        #expect(allowed)
        gate.observePartial("open calculator")
        allowed = gate.mayActOnPartial("open slack")
        #expect(!allowed)
    }

    @Test func finalizeClearsStaleCommit() {
        var gate = PartialActionGate()
        gate.observePartial("open slack")
        _ = gate.mayActOnPartial("open slack")
        gate.finalize("open calculator")
        let allowedAfterFinalize = gate.mayActOnPartial("open calculator")
        #expect(allowedAfterFinalize)
    }
}

@Suite struct WakeConversationTests {
    @Test func silenceWindowIsNinetySeconds() {
        #expect(WakeConversationTiming.silenceAfterSpeech == 90)
        #expect(WakeConversationTiming.silenceWhenEmpty == 90)
    }

    @Test func podcastFixturesNeverTriggerWake() {
        let hits = WakeFalseTriggerFixtures.falseTriggers()
        #expect(hits.isEmpty)
    }
}

@Suite struct OllamaVoiceLaneTests {
    @Test func ollamaUsesStandardPort() {
        #expect(AIProvider.ollama.localPort == 11434)
    }
}
