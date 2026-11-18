import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// When the microphone keeps changing (AirPods switching) and capture gives up, a talk turn and a
/// dictation end cleanly and say why, instead of staying on "listening" with a dead microphone.
/// No audio hardware: the turns are opened through test seams.
@MainActor
@Suite("Capture failure ends the turn", .serialized)
struct CaptureFailureEndsTurnTests {
    private static let hint = "The microphone kept changing, so Zeus stopped listening. Try again."

    private func talk() -> (VoiceTurnController, TopBarModel) {
        let notch = NotchController()
        let bar = TopBarModel()
        notch.topBar = bar
        return (VoiceTurnController(buddy: BuddyController(), notch: notch, brain: ClaudeCLIProvider()), bar)
    }

    private func dictation() throws -> DictationController {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capfail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return DictationController(topBar: TopBarModel(), store: DictationStore(root: root))
    }

    @Test func hintWordsTellThePersonWhatHappenedAndWhatToDo() {
        #expect(CaptureFailureHint.text(for: .configurationChanged) == Self.hint)
        #expect(!CaptureFailureHint.text(for: .durationLimit).contains("\u{2014}"))
        #expect(CaptureFailureHint.owns(session: 3, active: 3))
        #expect(!CaptureFailureHint.owns(session: 2, active: 3))
        #expect(!CaptureFailureHint.owns(session: 3, active: nil))
    }

    @Test func aTalkTurnEndsAndShowsTheHintWhenCaptureGivesUp() {
        let (controller, bar) = talk()
        controller.beginListeningForTesting(session: 7)
        var ended = 0
        controller.onListeningEnded = { ended += 1 }
        controller.handleCaptureFailure(session: 7, origin: 0, failure: .configurationChanged)
        #expect(!controller.isListeningForTesting)
        #expect(ended == 1, "the talk key machine must be told the turn is over")
        #expect(bar.cue == .hint(Self.hint))
    }

    @Test func aLateFailureFromAnOlderTalkSessionLeavesTheNewTurnAlone() {
        let (controller, bar) = talk()
        controller.beginListeningForTesting(session: 8)
        controller.handleCaptureFailure(session: 7, origin: 0, failure: .configurationChanged)
        #expect(controller.isListeningForTesting)
        #expect(bar.cue != .hint(Self.hint))
    }

    @Test func aFailureWhenNoTalkTurnIsListeningShowsNothing() {
        let (controller, bar) = talk()
        controller.handleCaptureFailure(session: 1, origin: 0, failure: .configurationChanged)
        #expect(bar.cue != .hint(Self.hint))
    }

    @Test func aListeningDictationEndsAndShowsTheHintWhenCaptureGivesUp() throws {
        let controller = try dictation()
        let turn = controller.beginListeningForTesting(session: 4)
        #expect(controller.flow.isListening)
        controller.handleCaptureFailure(session: 4, origin: turn, failure: .configurationChanged)
        #expect(controller.flow == .idle)
        #expect(controller.topBarModel.cue == .hint(Self.hint))
    }

    @Test func aStaleFailureLeavesTheCurrentDictationRunning() throws {
        let controller = try dictation()
        let turn = controller.beginListeningForTesting(session: 5)
        controller.handleCaptureFailure(session: 4, origin: turn, failure: .configurationChanged)
        controller.handleCaptureFailure(session: 5, origin: turn &+ 1, failure: .configurationChanged)
        #expect(controller.flow.isListening)
        #expect(controller.topBarModel.cue != .hint(Self.hint))
    }
}
