import Foundation
import Testing
@testable import ZeusCore

/// Elapsed time the abort reads. The test moves it; nothing sleeps for the budget.
private struct AbortClock {
    private(set) var milliseconds = 0

    mutating func advance(by delta: Int) {
        milliseconds += delta
    }
}

@Suite struct SpeakPathFixTests {
    @Test func identitySpeechOutputLeavesSamplesUnchanged() {
        let samples: [Float] = [0, -0.25, 0.5, 1]
        let step: any SpeechOutputProcessing = IdentitySpeechOutput()
        #expect(step.process(samples, sampleRate: 24_000) == samples)
    }

    @Test func onlyTheSyntheticVoiceIdIsSpoken() {
        #expect(VoiceSpeakAllowlist.accepts("zeus.synthetic"))
        #expect(!VoiceSpeakAllowlist.accepts("voice-1"))
        #expect(!VoiceSpeakAllowlist.accepts("en-US-Neural2-C"))
        #expect(!VoiceSpeakAllowlist.accepts("JBFqnCBsd6RMkjVDRZzb"))
    }

    @Test func theLiveAbortUsesTheDeclared700MillisecondBudget() {
        #expect(ProviderSpeakAbort.milliseconds == 700)
        #expect(ProviderSpeakAbort.milliseconds == ProviderLatencyVerdict.firstAudioP50Ms)
        #expect(ProviderSpeakAbort.shouldAbort(elapsedMs: 701, heardAudio: false))
        #expect(!ProviderSpeakAbort.shouldAbort(elapsedMs: 700, heardAudio: false))
        #expect(!ProviderSpeakAbort.shouldAbort(elapsedMs: 5_000, heardAudio: true))
    }

    /// Tony's S10 decision: a silent provider aborts when the clock reaches 1,400 ms, and not before.
    @Test func silentProviderAbortsAt1400MillisecondsNotBefore() {
        var clock = AbortClock()
        #expect(ProviderSpeakAbort.milliseconds == 1_400)
        clock.advance(by: 700)
        #expect(!ProviderSpeakAbort.shouldAbort(elapsedMs: clock.milliseconds, heardAudio: false))
        clock.advance(by: 699)
        #expect(clock.milliseconds == 1_399)
        #expect(!ProviderSpeakAbort.shouldAbort(elapsedMs: clock.milliseconds, heardAudio: false))
        clock.advance(by: 1)
        #expect(clock.milliseconds == 1_400)
        #expect(ProviderSpeakAbort.shouldAbort(elapsedMs: clock.milliseconds, heardAudio: false))
        #expect(!ProviderSpeakAbort.shouldAbort(elapsedMs: clock.milliseconds, heardAudio: true))
    }

    @Test func providerErrorsStayDistinct() {
        #expect(ProviderFailure.fromHTTPStatus(402) == .creditsUsedUp)
        #expect(ProviderFailure.fromHTTPStatus(400) == .badVoice)
        #expect(ProviderFailure.fromHTTPStatus(400, validating: true) == .unauthorized)
        #expect(ProviderFailure.fromHTTPStatus(0) == .offline)
        #expect(ProviderFailure.creditsUsedUp.pill == "Credits are used up")
        #expect(ProviderFailure.badVoice.pill == "That voice isn't available")
    }

    @Test func pcmArrivesAs24kFramesOf3200Samples() {
        var assembler = PCM24kAssembler()
        let one = Data(count: SpeechPCMFrame.byteCount)
        let frames = assembler.append(one)
        #expect(frames.count == 1)
        #expect(frames[0].sampleRate == 24_000)
        #expect(frames[0].samples.count == 3_200)
        #expect(assembler.append(Data(count: 100)).isEmpty)
    }

    @Test func fallbackNeverUsesTheReferenceClipVoice() {
        #expect(SyntheticFallbackOrder.engines == ["kokoro", "system"])
        #expect(!SyntheticFallbackOrder.engines.contains("chatterbox"))
    }
}
