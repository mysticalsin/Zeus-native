import Foundation
import Testing
@testable import ZeusCore

/// The default voice is local. A cloud key does not lead. An explicit owner pick still wins.
@Suite("Ultron voice: ElevenLabs first, Kokoro failsafe")
struct UltronElevenFirstTests {
    typealias A = UltronEngineAvailability
    private func engines(_ a: A, observed: [UltronEngine: Int] = [:]) -> [UltronEngine] {
        UltronEngineRouter.chain(choice: .auto, availability: a, observedFirstAudioMs: observed).map(\.engine)
    }

    // MARK: Defaults

    @Test func aKokoroStoredWithoutAnOwnerPickDoesNotBeatElevenLabs() {
        let engine = UltronVoicePlan.initialEngine(stored: .kokoro, userSelected: false, kokoroReady: true, elevenLabsKeyValid: true)
        #expect(engine == .kokoro)
    }

    @Test func aFreshInstallWithAKeyAndKokoroStartsOnElevenLabs() {
        #expect(UltronVoicePlan.initialEngine(stored: nil, userSelected: false, kokoroReady: true, elevenLabsKeyValid: true) == .kokoro)
        #expect(UltronVoicePlan.initialEngine(stored: nil, userSelected: false, kokoroReady: true, elevenLabsKeyValid: false) == .kokoro)
        #expect(UltronVoicePlan.initialEngine(stored: nil, userSelected: false, kokoroReady: false, elevenLabsKeyValid: false) == .system)
    }

    @Test func anExplicitOwnerPickStillWins() {
        for stored in [UltronVoicePlan.Engine.kokoro, .elevenLabs, .system] {
            #expect(UltronVoicePlan.initialEngine(stored: stored, userSelected: true, kokoroReady: true, elevenLabsKeyValid: true) == stored)
        }
    }

    @Test func elevenLabsIsTheDefaultProviderEvenWhenKokoroIsSetUp() {
        #expect(UltronVoicePlan.defaultProvider(kokoroReady: true, elevenLabsKeyValid: true) == .kokoro)
        #expect(UltronVoicePlan.defaultProvider(kokoroReady: false, elevenLabsKeyValid: true) == .kokoro)
    }

    @Test func kokoroIsTheDefaultProviderWithoutAUsableElevenLabsKey() {
        #expect(UltronVoicePlan.defaultProvider(kokoroReady: true, elevenLabsKeyValid: false) == .kokoro)
        #expect(UltronVoicePlan.defaultProvider(kokoroReady: false, elevenLabsKeyValid: false) == .kokoro)
    }

    @Test func autoOrderIsElevenLabsThenKokoroThenTheMacVoice() {
        #expect(engines(A(elevenLabsConfigured: true, kokoroReady: true)) == [.kokoro, .system])
    }

    @Test func aSlowElevenLabsStillLeadsAndTheTimeoutIsTheFailsafe() {
        // A demoted engine is never tried, so its slow reading could never recover.
        let both = A(elevenLabsConfigured: true, kokoroReady: true)
        #expect(engines(both, observed: [.elevenLabs: 3_400, .kokoro: 900]) == [.kokoro, .system])
    }

    // MARK: Failsafe

    @Test func everyWayElevenLabsCanFailLeavesKokoroNextThenTheMacVoice() {
        #expect(engines(A(elevenLabsConfigured: false, kokoroReady: true)) == [.kokoro, .system])
        #expect(engines(A(elevenLabsConfigured: true, elevenLabsPaused: true, kokoroReady: true)) == [.kokoro, .system])
        #expect(engines(A(elevenLabsConfigured: true, elevenLabsPaused: true, kokoroReady: false)) == [.system])
        #expect(engines(A(elevenLabsConfigured: true, kokoroReady: false)) == [.system])
    }

    @Test func everyRefusalPausesElevenLabsAndTheNextReplyGoesToKokoro() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        for status in [401, 402, 429, 500, 503] {
            let until = now.addingTimeInterval(UltronVoicePlan.pauseSeconds(status: status))
            let paused = UltronVoicePlan.isPaused(until: until, now: now)
            #expect(paused, "status \(status)")
            #expect(engines(A(elevenLabsConfigured: true, elevenLabsPaused: paused, kokoroReady: true)).first == .kokoro)
        }
    }

    @Test func aNetworkErrorOrTimeoutPausesElevenLabsBrieflySoTheNextSentencesGoToKokoro() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let until = now.addingTimeInterval(UltronVoicePlan.pauseSeconds(status: nil))
        #expect(UltronVoicePlan.pauseSeconds(status: nil) == 60)
        #expect(UltronVoicePlan.isPaused(until: until, now: now.addingTimeInterval(59)))
        #expect(!UltronVoicePlan.isPaused(until: until, now: until))
        #expect(engines(A(elevenLabsConfigured: true, elevenLabsPaused: true, kokoroReady: true)).first == .kokoro)
    }

    @Test func aBadKeyOrEmptyCreditsPauseForFifteenMinutesOtherRefusalsForOne() {
        #expect(UltronVoicePlan.pauseSeconds(status: 401) == 900)
        #expect(UltronVoicePlan.pauseSeconds(status: 402) == 900)
        #expect(UltronVoicePlan.pauseSeconds(status: 429) == 60)
        #expect(UltronVoicePlan.pauseSeconds(status: 500) == 60)
    }

    @Test func thePersistedPauseExpiresSoElevenLabsIsTriedAgainAfterCreditsReset() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let until = now.addingTimeInterval(UltronVoicePlan.pauseSeconds(status: 402))
        #expect(UltronVoicePlan.isPaused(until: until, now: now.addingTimeInterval(899)))
        #expect(!UltronVoicePlan.isPaused(until: until, now: until))
        #expect(!UltronVoicePlan.isPaused(until: nil, now: now))
        let after = !UltronVoicePlan.isPaused(until: until, now: until.addingTimeInterval(1))
        #expect(engines(A(elevenLabsConfigured: true, elevenLabsPaused: !after, kokoroReady: true)).first == .kokoro)
    }

    @Test func anExplicitKokoroPickLeadsAndElevenLabsStaysTheFallback() {
        let chain = UltronEngineRouter.chain(choice: .fixed(.kokoro), availability: A(elevenLabsConfigured: true, kokoroReady: true))
        #expect(chain.map(\.engine) == [.kokoro, .system])
    }

    // MARK: Same character

    @Test func kokoroSpeaksAsTheSameUltronCharacter() {
        #expect(UltronCloudVoice.kokoroVoice == "am_michael")
        #expect(UltronCloudVoice.kokoroSpeed < 1)
        #expect(UltronEffectParameters.defaultPercent == 75)
        #expect(!UltronEffectParameters.make(percent: Double(UltronEffectParameters.defaultPercent)).isNeutral)
    }
}
