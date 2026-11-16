import AVFoundation
import Foundation
import Testing
@testable import Zeus

/// The talk-turn voice path with an AirPods-style headset: capture survives a profile change, and
/// the microphone and output engine are used the way the turn needs them. No audio hardware.
@Suite("Talk turn voice", .serialized)
struct TalkTurnVoiceTests {
    private struct Boom: Error {}

    /// Spies in place of the engine: they record the order of calls.
    private final class Spy: @unchecked Sendable {
        var calls: [String] = []
        var tapAccepted = true
        var restartThrows = false
        var failures: [CaptureRecovery.Outcome] = []
    }

    private func fire(_ spy: Spy, cancelsTurn: Bool = false, ownsSession: Bool = true) -> CaptureRecovery.Action {
        CaptureRecovery.handle(
            cancelsTurn: cancelsTurn, ownsSession: ownsSession,
            cancelTurn: { spy.calls.append("cancel") },
            reinstallTap: { spy.calls.append("tap"); return spy.tapAccepted },
            restartEngine: { spy.calls.append("restart"); if spy.restartThrows { throw Boom() } },
            recoveryFailed: { spy.failures.append($0) })
    }

    @Test func aConfigurationChangeReinstallsTheTapThenRestartsTheEngineAndKeepsTheTurn() {
        let spy = Spy()
        #expect(fire(spy) == .rebuild)
        #expect(spy.calls == ["tap", "restart"])
        #expect(!spy.calls.contains("cancel"))
        #expect(spy.failures.isEmpty)
    }

    @Test func aChangeAfterTheTurnEndedDoesNothing() {
        let spy = Spy()
        #expect(fire(spy, ownsSession: false) == .ignore)
        #expect(spy.calls.isEmpty)
    }

    @Test func theExplanationPolicyStillCancelsInsteadOfRecovering() {
        let spy = Spy()
        #expect(fire(spy, cancelsTurn: true) == .cancelTurn)
        #expect(spy.calls == ["cancel"])
    }

    @Test func anInputWithoutAFormatWaitsForTheNextChangeInsteadOfEndingTheTurn() {
        let spy = Spy()
        spy.tapAccepted = false
        _ = fire(spy)
        #expect(spy.calls == ["tap"], "no restart without a tap")
        #expect(spy.failures == [.inputUnavailable])
        #expect(!CaptureRecovery.Outcome.inputUnavailable.endsTurn)
    }

    @Test func anEngineThatWillNotRestartIsReportedAndEndsTheTurn() {
        let spy = Spy()
        spy.restartThrows = true
        _ = fire(spy)
        #expect(spy.calls == ["tap", "restart"])
        #expect(spy.failures == [.restartFailed])
        #expect(CaptureRecovery.Outcome.restartFailed.endsTurn)
    }

    @Test func twoChangesInARowEachRebuild() {
        let spy = Spy()
        _ = fire(spy)
        _ = fire(spy)
        #expect(spy.calls == ["tap", "restart", "tap", "restart"])
    }

    // MARK: Output engine timing

    @Test @MainActor func aNewOutputChainHasStartedNoEngine() {
        #expect(UltronAudioChain().engineStarts == 0)
    }

    @Test func prewarmOnKeyPressNeverPreparesTheOutputEngine() throws {
        let text = try UIPolishSourceTests.source("Sources/Zeus/Voice/Speaker.swift")
        let start = try #require(text.range(of: "func prewarm() {"))
        let rest = text[start.upperBound...]
        let end = try #require(rest.range(of: "    func stop() {"))
        let body = String(rest[..<end.lowerBound])
        #expect(!body.contains("chain.prepare"), "key-down must not start playback")
        #expect(!body.contains("chain.schedule"))
    }

    /// Scheduling the first audio is what starts the output engine, once. A Mac with no output device
    /// cannot start one, so the count is only checked when the buffer was accepted.
    @Test @MainActor func theFirstScheduledAudioStartsTheOutputEngineOnce() throws {
        let chain = UltronAudioChain()
        chain.muted = true
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: UltronAudioChain.format, frameCapacity: 2_400))
        buffer.frameLength = 2_400
        #expect(chain.engineStarts == 0)
        guard chain.schedule(buffer) else { return }
        #expect(chain.engineStarts == 1)
        _ = chain.schedule(buffer)
        #expect(chain.engineStarts == 1, "a running engine is not started again")
        chain.stop()
    }

    // MARK: Chosen microphone

    @Test @MainActor func aTalkTurnListensOnTheMicrophoneChosenForDictation() {
        let suite = NSTemporaryDirectory() + "zeus.talkturn.mic.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = DictationSettings(defaults: defaults)
        let speech = SpeechInput()

        settings.microphoneUID = "BuiltInMicrophoneDevice"
        VoiceTurnController.applyChosenMicrophone(to: speech, from: settings)
        #expect(speech.deviceUID == "BuiltInMicrophoneDevice")

        settings.microphoneUID = nil
        VoiceTurnController.applyChosenMicrophone(to: speech, from: settings)
        #expect(speech.deviceUID == nil, "dropping the choice follows the system input again")
    }

    // MARK: Voice log location

    @Test func theVoiceLogStaysInTheOwnersFolderOutsideTests() {
        let home = URL(fileURLWithPath: "/Users/fixture", isDirectory: true)
        let dir = VoiceLog.logDirectory(environment: [:], runningTests: false, home: home,
                                        temporary: URL(fileURLWithPath: "/tmp/fixture", isDirectory: true))
        #expect(dir.path == "/Users/fixture/Library/Logs/Zeus")
    }

    @Test func underTestsTheVoiceLogGoesToATemporaryFolderNotTheOwnersLog() {
        let home = URL(fileURLWithPath: "/Users/fixture", isDirectory: true)
        let temp = URL(fileURLWithPath: "/tmp/fixture", isDirectory: true)
        let dir = VoiceLog.logDirectory(environment: [:], runningTests: true, home: home, temporary: temp)
        #expect(dir.path.hasPrefix("/tmp/fixture/"))
        #expect(!dir.path.contains("/Users/fixture"))
    }

    @Test func anExplicitLogFolderWinsEvenUnderTests() {
        let dir = VoiceLog.logDirectory(environment: ["ZEUS_LOG_DIR": "/tmp/chosen"], runningTests: true)
        #expect(dir.path == "/tmp/chosen")
    }

    @Test func thisTestRunIsDetectedAndItsLogIsNotTheOwnersLog() {
        #expect(VoiceLog.isRunningTests)
        if ProcessInfo.processInfo.environment["ZEUS_LOG_DIR"] == nil {
            #expect(!VoiceLog.url.path.contains("Library/Logs/Zeus"))
        }
    }

    // MARK: Per-turn diagnostics

    @Test func aTurnWithNothingHeardNamesTheDeviceFormatFramesAndConfigChanges() {
        let diagnostics = CaptureDiagnostics(deviceName: "AirPods Pro", sampleRate: 24_000, channels: 1,
                                             frames: 0, configChanges: 1)
        #expect(diagnostics.nothingHeardSummary == "nothing heard: AirPods Pro, 24000 Hz 1 ch, 0 frames, 1 config change")
    }

    @Test func theConfigChangeCountIsPluralisedAndFramesAreReported() {
        let diagnostics = CaptureDiagnostics(deviceName: "MacBook Pro Microphone", sampleRate: 48_000, channels: 1,
                                             frames: 96_000, configChanges: 2)
        #expect(diagnostics.nothingHeardSummary
                == "nothing heard: MacBook Pro Microphone, 48000 Hz 1 ch, 96000 frames, 2 config changes")
        #expect(CaptureDiagnostics().nothingHeardSummary
                == "nothing heard: unknown input, 0 Hz 0 ch, 0 frames, 0 config changes")
    }

    @Test func theSummaryHasNoDashAndSurvivesANonFiniteRate() {
        let diagnostics = CaptureDiagnostics(deviceName: "X", sampleRate: .nan, channels: 2, frames: 5, configChanges: 0)
        #expect(!diagnostics.nothingHeardSummary.contains("\u{2014}"))
        #expect(diagnostics.nothingHeardSummary.contains("0 Hz 2 ch"))
    }

    @Test func aFlappingLinkEndsTheTurnAfterTheLimitButAHeadsetSettlingDoesNot() {
        #expect(!CaptureRecovery.exceedsLimit(changes: 3))
        #expect(!CaptureRecovery.exceedsLimit(changes: CaptureRecovery.maximumChanges))
        #expect(CaptureRecovery.exceedsLimit(changes: CaptureRecovery.maximumChanges + 1))
    }

    @Test func aBufferInTheHeadsetFormatIsConvertedToTheRequestFormat() throws {
        let headset = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false))
        let original = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false))
        let converter = try #require(AVAudioConverter(from: headset, to: original))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: headset, frameCapacity: 2_400))
        buffer.frameLength = 2_400
        for index in 0..<2_400 { buffer.floatChannelData![0][index] = sin(Float(index) * 0.05) * 0.3 }
        let converted = try #require(SpeechInput.convert(buffer, with: converter))
        #expect(converted.format == original)
        #expect(converted.frameLength > 2_000)
    }
}
