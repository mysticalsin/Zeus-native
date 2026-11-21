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
}
