import AVFoundation
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// `SpeechInput.handleConfigurationChange` with a fake engine: the stop race around the engine restart, and the retry
/// for an input with no usable format. No audio hardware.
@Suite("Speech input recovery", .serialized)
struct SpeechInputRecoveryTests {
    private struct Boom: Error {}

    private final class FakeEngine: CaptureEngine, @unchecked Sendable {
        var calls: [String] = []
        var running = false
        var format: AVAudioFormat?
        var onFormatRead: () -> Void = {}
        var onTapInstalled: () -> Void = {}
        var onStart: () -> Void = {}
        var isRunning: Bool { running }
        func inputFormat() -> AVAudioFormat? { calls.append("format"); onFormatRead(); return format }
        func installInputTap(format: AVAudioFormat, block: @escaping AVAudioNodeTapBlock) { calls.append("installTap"); onTapInstalled() }
        func removeInputTap() { calls.append("removeTap") }
        func prepare() { calls.append("prepare") }
        func start() throws { calls.append("start"); running = true; onStart() }
        func stop() { calls.append("stop"); running = false }
    }

    private final class Rig: @unchecked Sendable {
        let input = SpeechInput()
        let engine = FakeEngine()
        var scheduled: [() -> Void] = []
        var failures: [SpeechInput.CaptureFailure] = []
        var converterRequests = 0
        var converterResult: AVAudioConverter?
        var session = 0

        init(format: AVAudioFormat?, requestFormat: AVAudioFormat? = nil) {
            engine.format = format
            session = input.beginSessionForTesting(requestFormat: requestFormat)
            input.onCaptureFailure = { [unowned self] _, _, failure in failures.append(failure) }
        }

        func change() {
            input.handleConfigurationChange(
                engine: engine, session: session, origin: 0, policy: .init(), startedAt: 0,
                makeConverter: { [unowned self] _, _ in converterRequests += 1; return converterResult },
                scheduleRetry: { [unowned self] _, work in scheduled.append(work) })
        }

        /// Runs the retries the way the main queue would, until none is left.
        func drain() {
            while !scheduled.isEmpty { scheduled.removeFirst()() }
        }
    }

    private func format(_ rate: Double) throws -> AVAudioFormat {
        try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false))
    }

    // MARK: stop race

    @Test func aStopBetweenTheTapAndTheRestartNeverStartsTheEngine() throws {
        let rig = Rig(format: try format(48_000))
        rig.engine.onTapInstalled = { rig.input.cancel() }
        rig.change()
        #expect(rig.engine.calls.contains("installTap"))
        #expect(!rig.engine.calls.contains("start"), "the turn is over: the mic must not reopen")
        #expect(!rig.engine.isRunning)
    }

    @Test func aStopWhileTheEngineIsStartingLeavesItStoppedWithTheTapRemoved() throws {
        let rig = Rig(format: try format(48_000))
        rig.engine.onStart = { rig.input.cancel() }
        rig.change()
        let calls = rig.engine.calls
        let start = try #require(calls.firstIndex(of: "start"))
        #expect(Array(calls[(start + 1)...]) == ["stop", "removeTap"], "\(calls)")
        #expect(!rig.engine.isRunning)
    }

    @Test func aChangeThatSettlesNormallyKeepsTheEngineRunningWithItsTap() throws {
        let rig = Rig(format: try format(48_000))
        rig.change()
        #expect(rig.engine.calls == ["format", "removeTap", "installTap", "prepare", "start"])
        #expect(rig.engine.isRunning)
        #expect(rig.failures.isEmpty)
    }

    // MARK: no usable format

    @Test func anInputWithoutAFormatRetriesAndEndsTheTurnAfterTheLimit() throws {
        let rig = Rig(format: nil)
        rig.change()
        #expect(rig.scheduled.count == 1, "the first miss waits for the next notification or the retry")
        #expect(rig.failures.isEmpty)
        rig.drain()
        #expect(rig.failures == [.configurationChanged], "the turn ends once, after \(CaptureRecovery.maximumChanges) retries")
        #expect(!rig.engine.calls.contains("start"))
        #expect(rig.engine.calls.filter { $0 == "format" }.count == CaptureRecovery.maximumChanges)
    }

    @Test func noConverterIsAskedForWhenTheFormatIsUnchanged() throws {
        let rig = Rig(format: try format(48_000), requestFormat: try format(48_000))
        rig.change()
        #expect(rig.converterRequests == 0)
        #expect(rig.engine.isRunning)
    }
}
