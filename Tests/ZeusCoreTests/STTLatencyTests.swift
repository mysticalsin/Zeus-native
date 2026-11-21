import Foundation
import Testing
import ZeusCore

@Suite("STT latency")
struct STTLatencyTests {
    @Test func endpointFiresWithinBudgetAfterSilenceOnAnInjectedClock() {
        var clock = STTClock()
        var turn = STTLiveTurn(path: .talkHold, policy: .production, endOnSilence: true)
        clock.advance(to: 0)
        turn.keyDown(clock: clock)
        clock.advance(to: 15)
        turn.captureStarted(clock: clock)
        clock.advance(to: 40)
        turn.feed(clock: clock, rms: 0.05, partialToken: 1)
        clock.advance(to: 480)
        turn.feed(clock: clock, rms: 0.001, partialToken: 1)
        clock.advance(to: 880)
        turn.feed(clock: clock, rms: 0.001, partialToken: 1)

        let silence = turn.trace.offset(.silenceDetected)
        let endpoint = turn.trace.offset(.endpointFired)
        #expect(silence == 480)
        #expect(endpoint == 880)
        #expect(endpoint! - silence! <= STTSessionPolicy.fixed.silenceToEndpointMs)
    }

    @Test func theSameSilenceBudgetHoldsForMurmur() {
        let turn = STTLiveTurn.replay(path: .murmurTap, policy: .production, events: STTLatencyHarness.silenceEvents)
        #expect(turn.trace.offset(.endpointFired) == 880)
        #expect(turn.trace.offset(.silenceDetected) == 480)
    }

    @Test func theModelIsLoadedOnceAndReused() {
        var gate = STTModelGate()
        _ = gate.prewarm(policy: .production)
        let first = gate.beginUtterance(policy: .production)
        let second = gate.beginUtterance(policy: .production)
        #expect(gate.loadCount == 1)
        #expect(!first)
        #expect(!second)
        #expect(gate.ready)
    }

    @Test func theFinalIsDeliveredWithinBudgetOfTheEndpointWhenTheRecognizerNeverCallsBack() {
        for path in STTPath.allCases {
            let turn = STTLiveTurn.replay(path: path, policy: .production, events: STTLatencyHarness.releaseEvents, endOnSilence: false)
            let endpoint = turn.trace.offset(.endpointFired)!
            let final = turn.trace.offset(.finalTranscript)!
            let delivered = turn.trace.offset(.deliveredToUI)!
            let hop = STTSessionPolicy.fixed.deliveredHopMs(for: path)
            let cancelled = turn.taskCancelled
            let failure = turn.failure
            #expect(final - endpoint <= STTSessionPolicy.fixed.endpointToFinalMs)
            #expect(delivered - final <= hop)
            #expect(cancelled)
            #expect(failure == .none)
        }
    }

    @Test func aRecognizerThatNeverCallsBackIsNotLeftHanging() {
        let giveUp = STTSessionPolicy.production.batchGiveUpMs(audioMs: 1_000)
        #expect(giveUp <= 2_000)
        #expect(giveUp != 8_000)
        #expect(giveUp != 20_000)
        #expect(giveUp != 45_000)
        #expect(!STTSessionPolicy.production.allowsServerRoundTrip)
    }

    @Test func failureRateIsZeroWhenAPartialWasAlreadyHeard() {
        let lines = STTLatencyHarness.failureReport(policy: .production, turns: 4)
        #expect(lines.count == 2)
        for path in STTPath.allCases {
            var ledger = STTFailureLedger()
            for _ in 0..<4 {
                let turn = STTLiveTurn.replay(path: path, policy: .production, events: STTLatencyHarness.releaseEvents, endOnSilence: false)
                ledger.record(path: path, failure: turn.failure)
            }
            #expect(ledger.rate(path) == 0)
        }
    }

    @Test func theTraceKeepsTheFourGroupsAndNeverCarriesTranscriptText() {
        let turn = STTLiveTurn.replay(path: .talkHold, policy: .production, events: STTLatencyHarness.releaseEvents, endOnSilence: false)
        let report = turn.trace.grouped(failure: turn.failure)
        #expect(report.contains("capture: capture_start="))
        #expect(report.contains("vad: speech_start="))
        #expect(report.contains("silence_detected="))
        #expect(report.contains("endpoint_fired="))
        #expect(report.contains("asr: model_ready="))
        #expect(report.contains("first_partial="))
        #expect(report.contains("final_transcript="))
        #expect(report.contains("delivery: delivered_to_ui="))
        #expect(report.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || "=_:.- \n".unicodeScalars.contains(scalar)
        })
    }

    @Test func latencyRegressionBothPathsStayInsideTheBudget() {
        for path in STTPath.allCases {
            let before = STTLiveTurn.replay(path: path, policy: .legacy, events: STTLatencyHarness.releaseEvents, endOnSilence: false)
            let after = STTLiveTurn.replay(path: path, policy: .production, events: STTLatencyHarness.releaseEvents, endOnSilence: false)
            let beforeEndpoint = before.trace.offset(.endpointFired)!
            let afterEndpoint = after.trace.offset(.endpointFired)!
            let beforeFinalGap = before.trace.offset(.finalTranscript)! - beforeEndpoint
            let afterFinalGap = after.trace.offset(.finalTranscript)! - afterEndpoint
            let afterHop = after.trace.offset(.deliveredToUI)! - after.trace.offset(.finalTranscript)!
            let beforeFailure = before.failure
            let afterFailure = after.failure
            let beforeCancelled = before.taskCancelled
            let afterCancelled = after.taskCancelled
            #expect(beforeFinalGap == 2_500)
            #expect(beforeFailure == .hang)
            #expect(!beforeCancelled)
            #expect(afterFinalGap <= 450)
            #expect(afterHop <= STTSessionPolicy.fixed.deliveredHopMs(for: path))
            #expect(after.trace.offset(.captureStart)! - after.trace.offset(.keyDown)! <= STTSessionPolicy.fixed.keyDownToCaptureMs)
            #expect(afterFailure == .none)
            #expect(afterCancelled)
            #expect(after.trace.offset(.keyDown) == 0)
            #expect(after.trace.offset(.speechStart) != nil)
            #expect(after.trace.offset(.firstPartial) != nil)
            #expect(after.trace.offset(.modelReady) == 0)
        }
    }

    @Test func aMidPhrasePauseDoesNotBecomeTheEndpointSilence() {
        var clock = STTClock()
        var turn = STTLiveTurn(path: .talkHold, policy: .production, endOnSilence: false)
        clock.advance(to: 0)
        turn.keyDown(clock: clock)
        clock.advance(to: 40)
        turn.feed(clock: clock, rms: 0.05, partialToken: 1)
        clock.advance(to: 200)
        turn.feed(clock: clock, rms: 0.001, partialToken: 1)
        clock.advance(to: 500)
        turn.feed(clock: clock, rms: 0.05, partialToken: 2)
        clock.advance(to: 800)
        turn.feed(clock: clock, rms: 0.001, partialToken: 2)
        clock.advance(to: 900)
        turn.keyUp(clock: clock)
        let silence = turn.trace.offset(.silenceDetected)
        let endpoint = turn.trace.offset(.endpointFired)
        #expect(silence == 800)
        #expect(endpoint == 900)
        #expect(endpoint! - silence! <= STTSessionPolicy.fixed.silenceToEndpointMs)
    }

    @Test func aLateDeliveryDoesNotCloseTheNextUtterance() {
        var book = STTUtteranceBook()
        let first = book.begin(path: .talkHold, atMs: 0)
        let second = book.begin(path: .murmurTap, atMs: 100)
        let applied = book.deliver(generation: first, atMs: 180)
        let delivered = book.trace.offset(.deliveredToUI)
        #expect(second == first + 1)
        #expect(!applied)
        #expect(delivered == nil)
        #expect(book.trace.path == .murmurTap)
    }

    @Test func rapidStartStopCyclesDoNotCrossDeliver() {
        var book = STTUtteranceBook()
        for index in 0..<20 {
            let at = index * 100
            let path: STTPath = index.isMultiple(of: 2) ? .talkHold : .murmurTap
            let id = book.begin(path: path, atMs: at)
            let captured = book.mark(.captureStart, atMs: at + 10, generation: id)
            let ended = book.mark(.endpointFired, atMs: at + 40, generation: id)
            #expect(captured)
            #expect(ended)
            if index > 0 {
                let stale = book.deliver(generation: id - 1, atMs: at + 50)
                #expect(!stale)
            }
            let wrote = book.deliver(generation: id, atMs: at + 60)
            let shown = book.trace.offset(.deliveredToUI)
            #expect(wrote)
            #expect(shown == 60)
            #expect(book.trace.path == path)
        }
    }

    @Test func cancelDropsALateDeliver() {
        var book = STTUtteranceBook()
        let id = book.begin(path: .talkHold, atMs: 0)
        book.cancel(generation: id)
        let late = book.deliver(generation: id, atMs: 80)
        #expect(!late)
        #expect(book.trace.offset(.deliveredToUI) == nil)
        let next = book.begin(path: .murmurTap, atMs: 100)
        let stale = book.deliver(generation: id, atMs: 120)
        let fresh = book.deliver(generation: next, atMs: 140)
        #expect(!stale)
        #expect(fresh)
        #expect(book.trace.offset(.deliveredToUI) == 40)
    }

    @Test func aLongSilenceEndpointsAtTheBudgetNotAtTheLateSample() {
        var clock = STTClock()
        var turn = STTLiveTurn(path: .murmurTap, policy: .production, endOnSilence: true)
        clock.advance(to: 0)
        turn.keyDown(clock: clock)
        clock.advance(to: 40)
        turn.feed(clock: clock, rms: 0.05, partialToken: 1)
        clock.advance(to: 100)
        turn.feed(clock: clock, rms: 0.001, partialToken: 1)
        clock.advance(to: 10_000)
        turn.feed(clock: clock, rms: 0.001, partialToken: 1)
        let silence = turn.trace.offset(.silenceDetected)
        let endpoint = turn.trace.offset(.endpointFired)
        #expect(silence == 100)
        #expect(endpoint == 100 + STTSessionPolicy.fixed.silenceToEndpointMs)
        #expect(endpoint != 10_000)
    }

    @Test func endpointBoundariesKillComparisonMutants() {
        let budget = STTSessionPolicy.fixed.silenceToEndpointMs
        let silenceAt = 100
        func endpoint(at sample: Int) -> Int? {
            var clock = STTClock()
            var turn = STTLiveTurn(path: .talkHold, policy: .fixed, endOnSilence: true)
            clock.advance(to: 0)
            turn.keyDown(clock: clock)
            clock.advance(to: 40)
            turn.feed(clock: clock, rms: 0.05, partialToken: 1)
            clock.advance(to: silenceAt)
            turn.feed(clock: clock, rms: 0.001, partialToken: 1)
            clock.advance(to: sample)
            turn.feed(clock: clock, rms: 0.001, partialToken: 1)
            return turn.trace.offset(.endpointFired)
        }
        let early = endpoint(at: silenceAt + budget - 1)
        let exact = endpoint(at: silenceAt + budget)
        let late = endpoint(at: silenceAt + budget + 1)
        #expect(early == nil)
        #expect(exact == silenceAt + budget)
        #expect(late == silenceAt + budget + 1)
    }

    @Test func aStaleMarkDoesNotWriteTheOpenUtterance() {
        var book = STTUtteranceBook()
        let first = book.begin(path: .talkHold, atMs: 0)
        let second = book.begin(path: .murmurTap, atMs: 100)
        let wrote = book.mark(.speechStart, atMs: 150, generation: first)
        let speech = book.trace.offset(.speechStart)
        #expect(second == first + 1)
        #expect(!wrote)
        #expect(speech == nil)
    }

    @Test func generationZeroIsNotAnOpenUtterance() {
        var book = STTUtteranceBook()
        let wrote = book.deliver(generation: 0, atMs: 10)
        let delivered = book.trace.offset(.deliveredToUI)
        let allowed = STTUtteranceBook.accepts(owner: 0, current: 0, cancelled: false)
        #expect(!wrote)
        #expect(delivered == nil)
        #expect(!allowed)
    }

    @Test func anOlderCancelDoesNotCloseTheNewerUtterance() {
        var book = STTUtteranceBook()
        let first = book.begin(path: .talkHold, atMs: 0)
        let second = book.begin(path: .murmurTap, atMs: 100)
        book.cancel(generation: first)
        let wrote = book.deliver(generation: second, atMs: 140)
        let delivered = book.trace.offset(.deliveredToUI)
        #expect(wrote)
        #expect(delivered == 40)
        #expect(!book.cancelled)
    }

    @Test func aChangedTokenDuringSilenceIsSpeechOnTheFixedPolicy() {
        let budget = STTSessionPolicy.fixed.silenceToEndpointMs
        var clock = STTClock()
        var turn = STTLiveTurn(path: .talkHold, policy: .fixed, endOnSilence: true)
        clock.advance(to: 0)
        turn.keyDown(clock: clock)
        clock.advance(to: 40)
        turn.feed(clock: clock, rms: 0.05, partialToken: 1)
        clock.advance(to: 100)
        turn.feed(clock: clock, rms: 0.001, partialToken: 1)
        clock.advance(to: 100 + budget - 1)
        turn.feed(clock: clock, rms: 0.001, partialToken: 2)
        clock.advance(to: 100 + budget)
        turn.feed(clock: clock, rms: 0.001, partialToken: 2)
        let endpoint = turn.trace.offset(.endpointFired)
        #expect(STTLiveTurn.partialChanged(last: nil, token: 1))
        #expect(!STTLiveTurn.partialChanged(last: 1, token: 1))
        #expect(STTLiveTurn.partialChanged(last: 1, token: 2))
        #expect(endpoint == nil)
    }

    @Test func aCancelledDeliverIsRefused() {
        let open = STTUtteranceBook.accepts(owner: 1, current: 1, cancelled: false)
        let closed = STTUtteranceBook.accepts(owner: 1, current: 1, cancelled: true)
        #expect(open)
        #expect(!closed)
    }

    @Test func aStaleBufferDoesNotSetSpeechOrSilence() {
        var book = STTUtteranceBook()
        _ = book.begin(path: .talkHold, atMs: 0)
        let speech = book.noteLoudness(rms: 0.05, atMs: 20, bufferSession: 3, currentSession: 4)
        let silence = book.noteLoudness(rms: 0.0, atMs: 40, bufferSession: 3, currentSession: 4)
        #expect(!speech)
        #expect(!silence)
        #expect(book.trace.offset(.speechStart) == nil)
        #expect(book.trace.offset(.silenceDetected) == nil)
        let live = book.noteLoudness(rms: 0.05, atMs: 60, bufferSession: 4, currentSession: 4)
        #expect(live)
        #expect(book.trace.offset(.speechStart) == 60)
    }

    @Test func quietReachesExactlyAtTheHandsFreeThreshold() {
        let threshold = STTQuiet.handsFreeSilenceMs
        let at = STTQuiet.reached(quietForMs: threshold, thresholdMs: threshold)
        let before = STTQuiet.reached(quietForMs: threshold - 1, thresholdMs: threshold)
        let after = STTQuiet.reached(quietForMs: threshold + 1, thresholdMs: threshold)
        #expect(threshold == 1_000)
        #expect(at)
        #expect(!before)
        #expect(after)
    }
}
