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

    // MARK: start through an injected engine

    private final class StartFake: CaptureEngine, @unchecked Sendable {
        let object = NSObject()
        var calls: [String] = []
        var running = false
        var format: AVAudioFormat?
        var onPrepare: () -> Void = {}
        var onTapInstalled: () -> Void = {}
        var onFormatRead: () -> Void = {}
        var isRunning: Bool { running }
        var notificationObject: AnyObject? { object }
        func inputFormat() -> AVAudioFormat? { calls.append("format"); onFormatRead(); return format }
        func installInputTap(format: AVAudioFormat, block: @escaping AVAudioNodeTapBlock) { calls.append("installTap"); onTapInstalled() }
        func removeInputTap() { calls.append("removeTap") }
        func prepare() { calls.append("prepare"); onPrepare() }
        func start() throws { calls.append("start"); running = true }
        func stop() { calls.append("stop"); running = false }
    }

    private static func format(_ rate: Double) -> AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)
    }

    private func startRig() -> (SpeechInput, StartFake) {
        let input = SpeechInput()
        input.recognizes = false
        let fake = StartFake()
        fake.format = Self.format(48_000)
        input.captureEngineFactory = { fake }
        return (input, fake)
    }

    @Test func aStopDuringTheEngineStartLeavesTheMicClosedAndNoObserver() throws {
        let (input, fake) = startRig()
        fake.onPrepare = { input.cancel() } // the stop lands while the engine is not yet running
        try input.start()
        #expect(!fake.isRunning, "the mic must be closed again once start returns: \(fake.calls)")
        #expect(!input.hasConfigurationObserverForTesting)
    }

    @Test func aStopInTheObserverWindowLeavesNoObserverBehind() throws {
        let (input, fake) = startRig()
        input.beforeObserverStoreForTesting = { input.beforeObserverStoreForTesting = nil; input.cancel() }
        try input.start()
        #expect(!input.hasConfigurationObserverForTesting, "a stopped turn must not keep a live observer: \(fake.calls)")
        #expect(!fake.isRunning)
    }

    @Test func aFailedEngineStartReleasesItsOwnEngineAndObserver() throws {
        struct Boom: Error {}
        final class Failing: CaptureEngine, @unchecked Sendable {
            var calls: [String] = []
            var running = false
            var isRunning: Bool { running }
            var format = CaptureEngineLifecycleRaceTests.format(48_000)
            func inputFormat() -> AVAudioFormat? { format }
            func installInputTap(format: AVAudioFormat, block: @escaping AVAudioNodeTapBlock) {}
            func removeInputTap() { calls.append("removeTap") }
            func prepare() {}
            func start() throws { throw Boom() }
            func stop() { calls.append("stop") }
        }
        let input = SpeechInput()
        input.recognizes = false
        let failing = Failing()
        input.captureEngineFactory = { failing }
        #expect(throws: Boom.self) { try input.start() }
        #expect(failing.calls.contains("removeTap"))
        #expect(!input.hasConfigurationObserverForTesting)
    }

    // MARK: recovery

    @Test func aStopLandingWhileTheConverterIsBuiltReportsNoFailure() throws {
        let input = SpeechInput()
        let fake = StartFake()
        fake.format = Self.format(24_000)
        fake.running = true
        let session = input.beginSessionForTesting(requestFormat: Self.format(48_000), engine: fake)
        final class Seen: @unchecked Sendable { var failures: [SpeechInput.CaptureFailure] = [] }
        let seen = Seen()
        input.onCaptureFailure = { _, _, failure in seen.failures.append(failure) }
        input.handleConfigurationChange(
            engine: fake, session: session, origin: 0, policy: .init(), startedAt: 0,
            makeConverter: { _, _ in input.cancel(); return nil }, scheduleRetry: { _, _ in })
        #expect(seen.failures.isEmpty, "the turn was stopped: nothing to report \(seen.failures)")
    }

    @Test func aStopBetweenTheOwnershipCheckAndTheTapInstallLeavesNoTapOnTheStoppedEngine() throws {
        let input = SpeechInput()
        let fake = StartFake()
        fake.format = Self.format(48_000)
        fake.running = true
        let session = input.beginSessionForTesting(requestFormat: nil, engine: fake)
        fake.onFormatRead = { input.cancel() }
        input.handleConfigurationChange(engine: fake, session: session, origin: 0, policy: .init(), startedAt: 0,
                                        scheduleRetry: { _, _ in })
        #expect(fake.calls.last == "removeTap", "a tap installed after the stop must be removed: \(fake.calls)")
        #expect(!fake.isRunning)
    }
}
