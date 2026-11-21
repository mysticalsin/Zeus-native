import Testing
@testable import ZeusCore

/// Locks the final wait already on PR #249. The partial token stands in for words.
/// The trace stores no transcript text. This file does not change the wait or the
/// hands-free silence.
@Suite("Talk final wait regression")
struct TalkFinalWaitRegressionTests {
    @Test func aPartialWithNoFinalEndsAtFourHundredFiftyMillisecondsNotTwoAndAHalfSeconds() {
        let turn = release(policy: .production, recognizerFinalMs: nil)
        let endpoint = turn.trace.offset(.endpointFired)!
        let final = turn.trace.offset(.finalTranscript)!
        #expect(turn.hasText)
        #expect(final - endpoint == 450)
        #expect(final - endpoint != 2_500)
        #expect(turn.taskCancelled)
        #expect(turn.failure == .none)
        #expect(STTSessionPolicy.production.endpointToFinalMs == 450)

        let legacy = release(policy: .legacy, recognizerFinalMs: nil)
        let legacyGap = legacy.trace.offset(.finalTranscript)! - legacy.trace.offset(.endpointFired)!
        #expect(legacyGap == 2_500)
        #expect(!legacy.taskCancelled)
        #expect(legacy.failure == .hang)
    }

    @Test func aRecognizerFinalAtTwoHundredMillisecondsWins() {
        let keyUpMs = 600
        let turn = release(policy: .production, recognizerFinalMs: keyUpMs + 200)
        let endpoint = turn.trace.offset(.endpointFired)!
        let final = turn.trace.offset(.finalTranscript)!
        #expect(endpoint == keyUpMs)
        #expect(final - endpoint == 200)
        #expect(final - endpoint < STTSessionPolicy.production.endpointToFinalMs)
        #expect(turn.hasText)
        #expect(turn.taskCancelled)
        #expect(turn.failure == .none)
    }

    @Test func handsFreeSilenceStaysAtOneThousandMilliseconds() {
        #expect(STTQuiet.handsFreeSilenceMs == 1_000)
    }

    /// Key down, one partial, key up. `recognizerFinalMs` nil means the recognizer never sends isFinal.
    private func release(policy: STTSessionPolicy, recognizerFinalMs: Int?) -> STTLiveTurn {
        var clock = STTClock()
        var turn = STTLiveTurn(path: .talkHold, policy: policy, endOnSilence: false)
        clock.advance(to: 0)
        turn.keyDown(clock: clock)
        clock.advance(to: 40)
        turn.feed(clock: clock, rms: 0.05, partialToken: 1)
        clock.advance(to: 600)
        turn.keyUp(clock: clock, recognizerFinalMs: recognizerFinalMs)
        return turn
    }
}
