import Testing
@testable import ZeusCore

@Suite("Explain hold")
struct ExplainToggleTests {
    @Test func explainTurnIsIdleUntilACleanHold() {
        let turn = ExplainHold()
        #expect(turn.phase == .idle)
        #expect(turn.overlayUp == false)
        #expect(ExplainHold.confirm == VoiceKey.secondKeyConfirm)

        var tapped = ExplainHold()
        tapped.tap()
        #expect(tapped.phase == .idle)
        #expect(tapped.overlayUp == false)

        var loading = ExplainHold(engine: .loading)
        #expect(loading.phase == .loading)
        loading.advance(from: 0, to: ExplainHold.confirm)
        #expect(loading.overlayUp == false)
        #expect(loading.release(at: 1, transcript: "explain this") == .nothing)
        loading.engineReady()
        #expect(loading.phase == .idle)

        var failed = ExplainHold()
        failed.advance(from: 0, to: ExplainHold.confirm)
        failed.failEngine()
        #expect(failed.phase == .error)
        #expect(failed.overlayUp == false)
        #expect(failed.release(at: 1, transcript: "explain this") == .nothing)
        failed.engineReady()
        #expect(failed.phase == .idle)
    }

    @Test func holdingRightOptionAloneShowsTheOverlayAndReleaseProcesses() {
        var turn = ExplainHold()
        turn.advance(from: 0, to: 0)
        #expect(turn.overlayUp == false)
        #expect(turn.phase == .idle)
        turn.advance(from: 0, to: ExplainHold.confirm)
        #expect(turn.phase == .holding)
        #expect(turn.overlayUp == true)
        turn.advance(from: 0, to: ExplainHold.confirm + 0.05)
        #expect(turn.phase == .holding)
        let release = turn.release(at: ExplainHold.confirm + 0.1, transcript: "open Fixture")
        #expect(release == .process("open Fixture"))
        #expect(turn.phase == .processing)
        #expect(turn.overlayUp == true)
        turn.advance(from: 2, to: 2 + ExplainHold.confirm)
        #expect(turn.phase == .processing)
    }

    @Test func rightOptionDoesNotFireWhenAnotherKeyOrAClickHappensWhileItIsHeld() {
        var keyed = ExplainHold()
        keyed.advance(from: 0, to: ExplainHold.confirm)
        keyed.otherKeyDown()
        #expect(keyed.overlayUp == false)
        #expect(keyed.release(at: ExplainHold.confirm + 0.2, transcript: "open Fixture") == .nothing)

        var clicked = ExplainHold()
        clicked.advance(from: 0, to: ExplainHold.confirm)
        clicked.click()
        #expect(clicked.overlayUp == false)
        #expect(clicked.release(at: ExplainHold.confirm + 0.2, transcript: "open Fixture") == .nothing)

        var modifier = ExplainHold()
        modifier.otherKeyDown()
        modifier.advance(from: 0, to: 1)
        #expect(modifier.phase == .idle)
        #expect(modifier.overlayUp == false)
        #expect(modifier.release(at: 1.1, transcript: "open Fixture") == .nothing)
    }

    @Test func escapeWhileRightOptionIsHeldCancelsAndTheReleaseProcessesNothing() {
        var turn = ExplainHold()
        turn.advance(from: 0, to: ExplainHold.confirm)
        #expect(turn.overlayUp == true)
        turn.escape()
        #expect(turn.phase == .idle)
        #expect(turn.overlayUp == false)
        #expect(turn.release(at: ExplainHold.confirm + 0.2, transcript: "open Fixture") == .nothing)
    }

    @Test func controlOptionHoldToTalkIsUnchanged() {
        let owner = VoiceKey.owner(
            ofHold: .controlOption,
            talk: .controlOption,
            dictation: nil,
            pointing: .rightCommand,
            pointingEnabled: false,
            voiceOverOn: false,
            screenRecording: false,
            secondTalk: .rightOption
        )
        #expect(owner == .talk(screenAware: false))
        var turn = ExplainHold()
        turn.controlOptionHeld(from: 0, to: 1)
        #expect(turn.phase == .idle)
        #expect(turn.overlayUp == false)
        #expect(turn.release(at: 1.1, transcript: "open Fixture") == .nothing)
    }

    @Test func aTapDoesNotStartATurnAndOnlyAdvancesARunningWalk() {
        var idle = ExplainHold()
        idle.advance(from: 0, to: ExplainHold.confirm / 2)
        #expect(idle.release(at: ExplainHold.confirm / 2, transcript: "explain this") == .nothing)
        #expect(idle.phase == .idle)
        idle.tap()
        #expect(idle.phase == .idle)

        var turn = ExplainHold()
        turn.advance(from: 0, to: ExplainHold.confirm)
        let release = turn.release(at: ExplainHold.confirm + 0.1, transcript: "walk me through the fixture", steps: 3)
        #expect(release == .process("walk me through the fixture"))
        #expect(turn.walkStep == 1)
        #expect(turn.phase == .processing)
        turn.tap()
        #expect(turn.walkStep == 2)
        #expect(turn.phase == .processing)
        turn.finishCurrentStep()
        #expect(turn.walkStep == 3)
        turn.finishCurrentStep()
        #expect(turn.phase == .idle)
        #expect(turn.overlayUp == false)
        #expect(turn.walkStep == nil)
    }

    @Test func rightCommandHoldDoesNotStartAnExplainTurn() {
        var turn = ExplainHold()
        turn.rightCommandHeld(from: 0, to: 1)
        #expect(turn.phase == .idle)
        #expect(turn.overlayUp == false)
        #expect(turn.release(at: 1.1, transcript: "explain this") == .nothing)
        turn.tapRightCommand()
        #expect(turn.phase == .idle)
    }
}
