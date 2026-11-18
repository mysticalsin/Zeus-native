import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// When the microphone keeps changing (AirPods switching) and capture gives up, a talk turn and a
/// dictation end cleanly and say why, instead of staying on "listening" with a dead microphone.
/// press(), release(), begin() and finish() run for real; only the microphone start and stop, the
/// warm-ups, volume ducking, screen capture, permissions, media and sounds are swapped out.
@MainActor
@Suite("Capture failure ends the turn", .serialized)
struct CaptureFailureEndsTurnTests {
    private static let hint = "The microphone kept changing, so Zeus stopped listening. Try again."

    private struct NoMic: Error {}

    @MainActor
    private final class Quiet: LineSpeaking {
        var isSpeaking: Bool { false }
        var engineDescription: String { "quiet" }
        func speak(_ text: String, onStart: (@MainActor () -> Void)?) { onStart?() }
        func stop() {}
    }

    /// Counts the fake microphone's starts and stops, and what the stop would have returned.
    @MainActor
    private final class Mic {
        var starts = 0
        var stops = 0
        var session = 0
        var failsToStart = false
        var heard = ""
    }

    init() { ZeusSound.isMutedForTesting = true }

    private func talk(_ mic: Mic, session: Int = 11) -> (VoiceTurnController, TopBarModel) {
        let notch = NotchController()
        let bar = TopBarModel()
        notch.topBar = bar
        let controller = VoiceTurnController(buddy: BuddyController(), notch: notch, brain: ClaudeCLIProvider(),
                                             speaker: Quiet())
        var seams = VoiceTurnController.Seams.silent()
        seams.speechStart = { _ in
            if mic.failsToStart { throw NoMic() }
            mic.starts += 1
            mic.session = session
            return session
        }
        seams.speechStop = { _ in mic.stops += 1; return mic.heard }
        controller.seams = seams
        return (controller, bar)
    }

    private func dictation(_ mic: Mic, session: Int = 31) throws -> DictationController {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capfail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let controller = DictationController(topBar: TopBarModel(), store: DictationStore(root: root))
        var seams = DictationController.Seams()
        seams.access = { _, _ in .init(speech: true, microphone: true, language: true, onDevice: true) }
        seams.readyEngine = { nil }
        seams.pauseMedia = { _ in nil }
        seams.speechStart = { _, _ in
            if mic.failsToStart { throw NoMic() }
            mic.starts += 1
            return session
        }
        seams.speechStop = { _, _ in mic.stops += 1; return mic.heard }
        controller.seams = seams
        return controller
    }

    /// Lets queued main-actor work run until `done` holds (or gives up).
    private func settle(_ done: () -> Bool) async {
        for _ in 0..<200 where !done() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func hintWordsTellThePersonWhatHappenedAndWhatToDo() {
        #expect(CaptureFailureHint.text(for: .configurationChanged) == Self.hint)
        #expect(!CaptureFailureHint.text(for: .durationLimit).contains("\u{2014}"))
        #expect(CaptureFailureHint.owns(session: 3, active: 3))
        #expect(!CaptureFailureHint.owns(session: 2, active: 3))
        #expect(!CaptureFailureHint.owns(session: 3, active: nil))
    }

    // MARK: Talk

    @Test func aTalkPressInstallsTheHandlerAndReleaseClearsIt() {
        let mic = Mic()
        let (controller, _) = talk(mic)
        #expect(!controller.captureHandlerInstalledForTesting)
        #expect(controller.press())
        #expect(controller.isListeningForTesting)
        #expect(controller.captureHandlerInstalledForTesting, "press() must wire onCaptureFailure")
        #expect(controller.talkSessionForTesting == 11)
        controller.release()
        #expect(!controller.captureHandlerInstalledForTesting)
        #expect(controller.talkSessionForTesting == nil)
    }

    @Test func cancellingAListeningTalkTurnClearsTheHandler() {
        let (controller, _) = talk(Mic())
        #expect(controller.press())
        controller.cancelListening()
        #expect(!controller.isListeningForTesting)
        #expect(!controller.captureHandlerInstalledForTesting)
        #expect(controller.talkSessionForTesting == nil)
    }

    @Test func aTalkStartThatFailsLeavesNoHandlerAndNoSession() {
        let mic = Mic()
        mic.failsToStart = true
        let (controller, _) = talk(mic)
        #expect(!controller.press())
        #expect(!controller.isListeningForTesting)
        #expect(!controller.captureHandlerInstalledForTesting)
        #expect(controller.talkSessionForTesting == nil)
    }

    /// A key press during a live turn (a hands-free or wake turn) still cuts in and restarts the capture.
    @Test func aPressDuringALiveTurnStillCutsInWithAHandler() {
        let mic = Mic()
        let (controller, _) = talk(mic)
        #expect(controller.press())
        #expect(controller.press())
        #expect(mic.starts == 2)
        #expect(controller.isListeningForTesting)
        #expect(controller.captureHandlerInstalledForTesting)
    }

    /// A cut-in whose start throws leaves the live turn running with its handler and session.
    @Test func aFailedCutInKeepsTheLiveTurnsHandlerAndSession() {
        let mic = Mic()
        let (controller, _) = talk(mic)
        #expect(controller.press())
        mic.failsToStart = true
        #expect(!controller.press())
        #expect(mic.starts == 1)
        #expect(controller.isListeningForTesting)
        #expect(controller.captureHandlerInstalledForTesting)
        #expect(controller.talkSessionForTesting == 11)
    }

    @Test func aFailureDeliveredByTheSpeechInputEndsALivePressTurn() async {
        let (controller, bar) = talk(Mic())
        #expect(controller.press())
        var ended = 0
        controller.onListeningEnded = { ended += 1 }
        controller.deliverCaptureFailureForTesting(session: 11, failure: .configurationChanged)
        await settle { !controller.isListeningForTesting }
        #expect(!controller.isListeningForTesting)
        #expect(ended == 1, "the talk key machine must be told the turn is over")
        #expect(bar.cue == .hint(Self.hint))
        #expect(!controller.captureHandlerInstalledForTesting)
    }

    @Test func aReleaseThatBeatsTheMainHopNeverSendsThePartial() async {
        let mic = Mic()
        mic.heard = "open Spotify"
        let (controller, bar) = talk(mic)
        #expect(controller.press())
        // The failure lands on the audio thread; the key is released before its main-actor hop runs.
        controller.deliverCaptureFailureForTesting(session: 11, failure: .configurationChanged)
        controller.release()
        #expect(mic.stops == 0, "the half-heard words must not be read or sent")
        #expect(!controller.isListeningForTesting)
        #expect(bar.cue == .hint(Self.hint))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(mic.stops == 0)
        #expect(bar.cue == .hint(Self.hint))
    }

    @Test func aReleaseWithoutAFailureStillFinishesTheTurn() async {
        let mic = Mic()
        let (controller, _) = talk(mic)
        #expect(controller.press())
        controller.release()
        await settle { mic.stops > 0 }
        #expect(mic.stops == 1)
    }

    @Test func aCaptureFailureEndsAHandsFreeConversation() {
        let (controller, _) = talk(Mic())
        #expect(controller.press())
        controller.wakeConversationActiveForTesting = true
        controller.handleCaptureFailure(session: 11, origin: 0, failure: .configurationChanged)
        #expect(!controller.wakeConversationActiveForTesting, "a flapping microphone must not reopen another hands-free turn")
    }

    @Test func aTalkTurnEndsAndShowsTheHintWhenCaptureGivesUp() {
        let (controller, bar) = talk(Mic())
        controller.beginListeningForTesting(session: 7)
        var ended = 0
        controller.onListeningEnded = { ended += 1 }
        controller.handleCaptureFailure(session: 7, origin: 0, failure: .configurationChanged)
        #expect(!controller.isListeningForTesting)
        #expect(ended == 1)
        #expect(bar.cue == .hint(Self.hint))
    }

    @Test func aLateFailureFromAnOlderTalkSessionLeavesTheNewTurnAlone() {
        let (controller, bar) = talk(Mic())
        controller.beginListeningForTesting(session: 8)
        controller.handleCaptureFailure(session: 7, origin: 0, failure: .configurationChanged)
        #expect(controller.isListeningForTesting)
        #expect(bar.cue != .hint(Self.hint))
    }

    @Test func aFailureWhenNoTalkTurnIsListeningChangesNothing() {
        let (controller, bar) = talk(Mic())
        bar.show(.hint("Something else"))
        controller.handleCaptureFailure(session: 1, origin: 0, failure: .configurationChanged)
        #expect(bar.cue == .hint("Something else"))
    }

    // MARK: Dictation

    @Test func aDictationBeginInstallsTheHandlerAndCancelClearsIt() throws {
        let controller = try dictation(Mic())
        #expect(!controller.captureHandlerInstalledForTesting)
        controller.begin()
        #expect(controller.flow.isListening)
        #expect(controller.captureHandlerInstalledForTesting, "begin() must wire onCaptureFailure")
        controller.cancel()
        #expect(controller.flow == .idle)
        #expect(!controller.captureHandlerInstalledForTesting)
    }

    @Test func aDictationStartThatFailsLeavesNoHandler() throws {
        let mic = Mic()
        mic.failsToStart = true
        let controller = try dictation(mic)
        controller.begin()
        #expect(!controller.flow.isListening)
        #expect(!controller.captureHandlerInstalledForTesting)
    }

    @Test func aFailureDeliveredByTheSpeechInputEndsALiveDictation() async throws {
        let controller = try dictation(Mic())
        controller.begin()
        let turn = try #require(controller.flow.turn)
        controller.deliverCaptureFailureForTesting(session: 31, origin: turn, failure: .configurationChanged)
        await settle { controller.flow == .idle }
        #expect(controller.flow == .idle)
        #expect(controller.topBarModel.cue == .hint(Self.hint))
        #expect(!controller.captureHandlerInstalledForTesting)
    }

    @Test func finishingADictationClearsTheHandler() async throws {
        let mic = Mic()
        let controller = try dictation(mic)
        controller.begin()
        controller.finish()
        await settle { mic.stops > 0 && !controller.captureHandlerInstalledForTesting }
        #expect(mic.stops == 1)
        #expect(!controller.captureHandlerInstalledForTesting)
    }

    @Test func aListeningDictationEndsAndShowsTheHintWhenCaptureGivesUp() throws {
        let controller = try dictation(Mic())
        let turn = controller.beginListeningForTesting(session: 4)
        #expect(controller.flow.isListening)
        controller.handleCaptureFailure(session: 4, origin: turn, failure: .configurationChanged)
        #expect(controller.flow == .idle)
        #expect(controller.topBarModel.cue == .hint(Self.hint))
    }

    @Test func aStaleFailureLeavesTheCurrentDictationRunning() throws {
        let controller = try dictation(Mic())
        let turn = controller.beginListeningForTesting(session: 5)
        controller.handleCaptureFailure(session: 4, origin: turn, failure: .configurationChanged)
        controller.handleCaptureFailure(session: 5, origin: turn &+ 1, failure: .configurationChanged)
        #expect(controller.flow.isListening)
        #expect(controller.topBarModel.cue != .hint(Self.hint))
    }
}
