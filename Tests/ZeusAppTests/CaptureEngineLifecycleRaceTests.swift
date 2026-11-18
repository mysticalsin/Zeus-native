import AVFoundation
import Foundation
import Testing
@testable import Zeus

/// Stop and cancel run off the main actor while a new turn's `start` swaps the engine in. A late stop must close the
/// engine of the turn it belongs to, never the newer turn's. No audio hardware.
@Suite("Capture engine lifecycle race", .serialized)
struct CaptureEngineLifecycleRaceTests {
    private final class FakeEngine: CaptureEngine, @unchecked Sendable {
        var calls: [String] = []
        var running: Bool
        init(running: Bool) { self.running = running }
        var isRunning: Bool { running }
        func inputFormat() -> AVAudioFormat? { nil }
        func installInputTap(format: AVAudioFormat, block: @escaping AVAudioNodeTapBlock) { calls.append("installTap") }
        func removeInputTap() { calls.append("removeTap") }
        func prepare() { calls.append("prepare") }
        func start() throws { calls.append("start"); running = true }
        func stop() { calls.append("stop"); running = false }
    }

    @Test func aStopThatLosesTheRaceToANewStartLeavesTheNewEngineRunning() async {
        let input = SpeechInput()
        let old = FakeEngine(running: true)
        let fresh = FakeEngine(running: true)
        _ = input.beginSessionForTesting(requestFormat: nil, engine: old)
        input.beforeStopAudioForTesting = {
            input.beforeStopAudioForTesting = nil
            _ = input.beginSessionForTesting(requestFormat: nil, engine: fresh)
        }
        _ = await input.stop(waitForFinal: false)
        #expect(old.calls == ["stop", "removeTap"], "the stopped turn's engine is closed: \(old.calls)")
        #expect(fresh.calls.isEmpty, "the newer turn's engine must be untouched: \(fresh.calls)")
        #expect(fresh.isRunning)
        #expect(input.hasConfigurationObserverForTesting, "the newer turn keeps its configuration observer")
    }

    @Test func aCancelThatLosesTheRaceToANewStartLeavesTheNewEngineRunning() {
        let input = SpeechInput()
        let old = FakeEngine(running: true)
        let fresh = FakeEngine(running: true)
        _ = input.beginSessionForTesting(requestFormat: nil, engine: old)
        input.beforeStopAudioForTesting = {
            input.beforeStopAudioForTesting = nil
            _ = input.beginSessionForTesting(requestFormat: nil, engine: fresh)
        }
        input.cancel()
        #expect(old.calls == ["stop", "removeTap"], "\(old.calls)")
        #expect(fresh.calls.isEmpty, "\(fresh.calls)")
        #expect(fresh.isRunning)
        #expect(input.hasConfigurationObserverForTesting)
    }

    @Test func aStopWithNoRaceStillClosesTheEngineAndDropsTheObserver() async {
        let input = SpeechInput()
        let engine = FakeEngine(running: true)
        _ = input.beginSessionForTesting(requestFormat: nil, engine: engine)
        _ = await input.stop(waitForFinal: false)
        #expect(engine.calls == ["stop", "removeTap"], "\(engine.calls)")
        #expect(!input.hasConfigurationObserverForTesting)
    }

    @Test func anEngineStartedAfterTheTurnWasStoppedIsClosedAgain() {
        let input = SpeechInput()
        let engine = FakeEngine(running: false)
        let session = input.beginSessionForTesting(requestFormat: nil, engine: engine)
        input.cancel()
        engine.calls = []
        engine.running = true // `engine.start()` returned after the stop landed
        input.closeCaptureIfNotOwned(engine, session: session)
        #expect(engine.calls == ["stop", "removeTap"], "\(engine.calls)")
        #expect(!engine.isRunning)
    }

    @Test func anEngineStartedForALiveTurnIsLeftRunning() {
        let input = SpeechInput()
        let engine = FakeEngine(running: true)
        let session = input.beginSessionForTesting(requestFormat: nil, engine: engine)
        input.closeCaptureIfNotOwned(engine, session: session)
        #expect(engine.calls.isEmpty, "\(engine.calls)")
        #expect(engine.isRunning)
    }
}
