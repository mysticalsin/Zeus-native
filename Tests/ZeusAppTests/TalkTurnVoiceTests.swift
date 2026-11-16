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
}
