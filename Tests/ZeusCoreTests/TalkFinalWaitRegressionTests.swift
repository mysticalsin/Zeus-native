import Testing
@testable import ZeusCore

/// Push-to-talk final wait. The partial token stands in for words.
/// Hands-free silence is not read or written here.
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

    @Test func aFinalInsideTheCapAfterKeyUpReplacesTheProvisionalCap() {
        var turn = speak()
        var clock = STTClock(nowMs: 600)
        turn.keyUp(clock: clock)
        #expect(turn.trace.offset(.finalTranscript)! - turn.trace.offset(.endpointFired)! == 450)
        clock = STTClock(nowMs: 800)
        turn.keyUp(clock: clock, recognizerFinalMs: 800)
        let endpoint = turn.trace.offset(.endpointFired)!
        let final = turn.trace.offset(.finalTranscript)!
        #expect(endpoint == 600)
        #expect(final - endpoint == 200)
        #expect(turn.taskCancelled)
        #expect(turn.failure == .none)
    }

    @Test func aLateFinalStaysOnTheFourHundredFiftyCap() {
        var turn = speak()
        var clock = STTClock(nowMs: 600)
        turn.keyUp(clock: clock)
        clock = STTClock(nowMs: 1_600)
        turn.keyUp(clock: clock, recognizerFinalMs: 1_600)
        let endpoint = turn.trace.offset(.endpointFired)!
        let final = turn.trace.offset(.finalTranscript)!
        #expect(endpoint == 600)
        #expect(final - endpoint == STTSessionPolicy.production.endpointToFinalMs)
        #expect(final - endpoint == 450)
    }

    @Test func aSecondKeyUpDoesNotMoveTheEndpointOrExtendTheCap() {
        var turn = speak()
        var clock = STTClock(nowMs: 600)
        turn.keyUp(clock: clock, recognizerFinalMs: 800)
        clock = STTClock(nowMs: 2_000)
        turn.keyUp(clock: clock)
        #expect(turn.trace.offset(.endpointFired) == 600)
        #expect(turn.trace.offset(.finalTranscript)! - 600 == 200)
        clock = STTClock(nowMs: 2_100)
        turn.keyUp(clock: clock, recognizerFinalMs: 2_100)
        #expect(turn.trace.offset(.endpointFired) == 600)
        #expect(turn.trace.offset(.finalTranscript)! - 600 == 200)
    }

    /// Key down and one partial. The caller performs key-up.
    private func speak() -> STTLiveTurn {
        var clock = STTClock()
        var turn = STTLiveTurn(path: .talkHold, policy: .production, endOnSilence: false)
        clock.advance(to: 0)
        turn.keyDown(clock: clock)
        clock.advance(to: 40)
        turn.feed(clock: clock, rms: 0.05, partialToken: 1)
        return turn
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
