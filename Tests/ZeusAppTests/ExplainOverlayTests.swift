import Foundation
import Testing
@testable import ZeusCore

@Suite struct ExplainOverlayTests {
    private func screen() -> ExplainScreen {
        ExplainScreen(
            controls: [
                ExplainControl(id: "1", name: "Save", displayID: "main", backingScale: 1, frame: ExplainFrame(x: 1, y: 2, width: 3, height: 4), relevant: true),
                ExplainControl(id: "2", name: "Export", displayID: "side", backingScale: 2, frame: ExplainFrame(x: 8, y: 9, width: 10, height: 11), relevant: true),
            ],
            reduceMotion: false,
            engineReady: true,
            unsavedApps: []
        )
    }

    private func hold(_ turn: inout ExplainTurn, transcript: String) {
        let screen = screen()
        turn.handle(.rightOptionDown(at: 0), screen: screen, parse: ExplainTranscript.command)
        turn.handle(.confirm(at: 0.25), screen: screen, parse: ExplainTranscript.command)
        turn.handle(.rightOptionUp(at: 1, transcript: transcript), screen: screen, parse: ExplainTranscript.command)
    }

    @Test func theOverlayIsUpWhileHeldAndClicksPassThrough() {
        var turn = ExplainTurn()
        let screen = screen()
        turn.handle(.rightOptionDown(at: 0), screen: screen, parse: ExplainTranscript.command)
        #expect(turn.overlay.isUp)
        #expect(turn.overlay.ignoresMouseEvents)
        #expect(turn.overlay.windowCount == 1)
        turn.handle(.confirm(at: 0.25), screen: screen, parse: ExplainTranscript.command)
        #expect(turn.openedWindows == 1)
        turn.handle(.click, screen: screen, parse: ExplainTranscript.command)
        #expect(turn.overlay.isUp == false)
        #expect(turn.overlay.windowCount == 0)
        #expect(turn.openedWindows == 1)
    }

    @Test func pointerAndMarksMatchThePhraseOnEveryDisplayAndScale() {
        var turn = ExplainTurn()
        hold(&turn, transcript: "describe what's on my screen")
        turn.handle(.phrase(id: "2", at: 3), screen: screen(), parse: ExplainTranscript.command)
        let mark = turn.overlay.marks.first { $0.id == "2" }
        #expect(mark?.displayID == "side")
        #expect(mark?.backingScale == 2)
        #expect(mark?.frame == ExplainFrame(x: 8, y: 9, width: 10, height: 11))
        #expect(mark?.calledOut == true)
        #expect(turn.overlay.pointer?.frame == mark?.frame)
    }

    @Test func aClickForThePersonWaitsForTheExistingApprovalCard() {
        var turn = ExplainTurn()
        hold(&turn, transcript: "click Export for me")
        #expect(turn.didClick == false)
        #expect(turn.approval == .click("Export"))
        #expect(turn.overlay.pointer?.highlighted == true)
        turn.handle(.approvalDenied, screen: screen(), parse: ExplainTranscript.command)
        #expect(turn.didClick == false)
        var allowed = ExplainTurn()
        hold(&allowed, transcript: "click Export for me")
        allowed.handle(.approvalAllowed, screen: screen(), parse: ExplainTranscript.command)
        #expect(allowed.didClick == true)
    }

    @Test func voiceOverHearsHoldReleaseCancelAndTheMark() {
        var turn = ExplainTurn()
        let screen = screen()
        turn.handle(.rightOptionDown(at: 0), screen: screen, parse: ExplainTranscript.command)
        turn.handle(.confirm(at: 0.25), screen: screen, parse: ExplainTranscript.command)
        #expect(turn.announcements.contains("Holding"))
        turn.handle(.rightOptionUp(at: 1, transcript: "describe what's on my screen"), screen: screen, parse: ExplainTranscript.command)
        #expect(turn.announcements.contains("Released"))
        turn.handle(.phrase(id: "1", at: 2), screen: screen, parse: ExplainTranscript.command)
        #expect(turn.announcements.contains("Mark 1, Save"))
        turn.handle(.voiceOverCancel, screen: screen, parse: ExplainTranscript.command)
        #expect(turn.announcements.contains("Cancelled"))
        #expect(turn.overlay.isUp == false)
        #expect(turn.phase == .idle)
    }
}
