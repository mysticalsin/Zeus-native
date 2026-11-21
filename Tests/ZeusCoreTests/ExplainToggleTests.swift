import Foundation
import Testing
@testable import ZeusCore

@Suite struct ExplainToggleTests {
    private func readyScreen(reduceMotion: Bool = false, engineReady: Bool = true, unsaved: [String] = []) -> ExplainScreen {
        ExplainScreen(
            controls: [
                ExplainControl(id: "1", name: "Save", displayID: "main", backingScale: 1, frame: ExplainFrame(x: 10, y: 20, width: 80, height: 24), relevant: true),
                ExplainControl(id: "2", name: "Export", displayID: "external", backingScale: 2, frame: ExplainFrame(x: 40, y: 60, width: 90, height: 24), relevant: true),
                ExplainControl(id: "3", name: "Close", displayID: "main", backingScale: 1, frame: ExplainFrame(x: 140, y: 60, width: 70, height: 24), relevant: false),
            ],
            reduceMotion: reduceMotion,
            engineReady: engineReady,
            unsavedApps: unsaved
        )
    }

    private func fixtureParse(_ text: String) -> ExplainCommand {
        ExplainTranscript.command(for: text)
    }

    private func hold(_ turn: inout ExplainTurn, transcript: String, screen: ExplainScreen, at: TimeInterval = 0) {
        turn.handle(.rightOptionDown(at: at), screen: screen, parse: fixtureParse)
        turn.handle(.confirm(at: at + ExplainTurn.confirmSeconds), screen: screen, parse: fixtureParse)
        turn.handle(.rightOptionUp(at: at + 1, transcript: transcript), screen: screen, parse: fixtureParse)
    }

    @Test func explainTurnIsIdleUntilACleanHold() {
        #expect(ExplainPhase.names == ["idle", "holding", "processing", "loading", "error", "recovery"])
        #expect(!ExplainPhase.names.contains("toggle"))
        #expect(!ExplainPhase.names.contains("secondTap"))
        var turn = ExplainTurn()
        let screen = readyScreen()
        #expect(turn.phase == .idle)
        #expect(turn.openTurns == 0)
        turn.handle(.rightOptionDown(at: 0), screen: screen, parse: fixtureParse)
        #expect(turn.phase == .idle)
        #expect(turn.openTurns == 0)
        turn.handle(.confirm(at: ExplainTurn.confirmSeconds), screen: screen, parse: fixtureParse)
        #expect(turn.phase == .holding)
        #expect(turn.openTurns == 1)
        #expect(ExplainTurn.confirmSeconds == 0.25)
        #expect(ExplainTurn.confirmSeconds == VoiceKey.secondKeyConfirm)
    }

    @Test func holdingRightOptionAloneShowsTheOverlayAndReleaseProcesses() throws {
        let source = try bridgeSource()
        #expect(source.contains("FastIntent.parse"))
        #expect(!source.contains("SFSpeech"))
        #expect(!source.contains("Recognizer"))
        var turn = ExplainTurn()
        let screen = readyScreen()
        turn.handle(.rightOptionDown(at: 0), screen: screen, parse: fixtureParse)
        #expect(turn.overlay.isUp)
        #expect(turn.overlay.windowCount == 1)
        turn.handle(.confirm(at: 0.25), screen: screen, parse: fixtureParse)
        #expect(turn.phase == .holding)
        turn.handle(.rightOptionUp(at: 1, transcript: "explain this"), screen: screen, parse: fixtureParse)
        #expect(turn.processedOnRelease)
        #expect(turn.processedTranscripts == ["explain this"])
        #expect(turn.waitingForSecondPrompt == false)
        #expect(turn.phase == .processing)
    }

    @Test func rightOptionDoesNotFireWhenAnotherKeyOrAClickHappensWhileItIsHeld() {
        let screen = readyScreen()
        var keyed = ExplainTurn()
        keyed.handle(.rightOptionDown(at: 0), screen: screen, parse: fixtureParse)
        keyed.handle(.otherKeyDown, screen: screen, parse: fixtureParse)
        keyed.handle(.confirm(at: 0.25), screen: screen, parse: fixtureParse)
        keyed.handle(.rightOptionUp(at: 0.4, transcript: "explain this"), screen: screen, parse: fixtureParse)
        #expect(keyed.processedTranscripts.isEmpty)
        #expect(keyed.overlay.isUp == false)
        #expect(keyed.phase == .idle)

        var clicked = ExplainTurn()
        clicked.handle(.rightOptionDown(at: 0), screen: screen, parse: fixtureParse)
        clicked.handle(.confirm(at: 0.25), screen: screen, parse: fixtureParse)
        clicked.handle(.click, screen: screen, parse: fixtureParse)
        clicked.handle(.rightOptionUp(at: 0.8, transcript: "explain this"), screen: screen, parse: fixtureParse)
        #expect(clicked.processedTranscripts.isEmpty)
        #expect(clicked.overlay.isUp == false)
    }

    @Test func escapeWhileRightOptionIsHeldCancelsAndTheReleaseProcessesNothing() {
        var turn = ExplainTurn()
        let screen = readyScreen()
        turn.handle(.rightOptionDown(at: 0), screen: screen, parse: fixtureParse)
        turn.handle(.confirm(at: 0.25), screen: screen, parse: fixtureParse)
        turn.handle(.escape, screen: screen, parse: fixtureParse)
        #expect(turn.overlay.isUp == false)
        #expect(turn.announcements.contains("Cancelled"))
        turn.handle(.rightOptionUp(at: 1, transcript: "explain this"), screen: screen, parse: fixtureParse)
        #expect(turn.processedTranscripts.isEmpty)
        #expect(turn.phase == .idle)
    }

    @Test func controlOptionHoldToTalkIsUnchanged() {
        var turn = ExplainTurn()
        let screen = readyScreen()
        turn.handle(.controlOptionDown, screen: screen, parse: fixtureParse)
        turn.handle(.controlOptionUp, screen: screen, parse: fixtureParse)
        #expect(turn.talkTurns == 1)
        #expect(turn.talkSends == 1)
        #expect(turn.phase == .idle)
        #expect(turn.overlay.isUp == false)
        #expect(turn.openTurns == 0)
    }

    @Test func aShortTapDoesNotStartListening() {
        var turn = ExplainTurn()
        let screen = readyScreen()
        turn.handle(.rightOptionDown(at: 0), screen: screen, parse: fixtureParse)
        turn.handle(.rightOptionUp(at: 0.1, transcript: "explain this"), screen: screen, parse: fixtureParse)
        #expect(turn.phase == .idle)
        #expect(turn.processedTranscripts.isEmpty)
        #expect(turn.overlay.isUp == false)
    }

    @Test func holdThenOpenUsesFastIntentOpenApp() throws {
        let source = try bridgeSource()
        #expect(source.contains("case .openApp"))
        #expect(source.contains("FastIntent.parse"))
        var turn = ExplainTurn()
        hold(&turn, transcript: "open FixtureApp", screen: readyScreen())
        #expect(turn.openedApps == ["FixtureApp"])
        #expect(turn.processedOnRelease)
        #expect(turn.waitingForSecondPrompt == false)
    }

    @Test func holdThenCloseUsesFastIntentQuitApp() throws {
        let source = try bridgeSource()
        #expect(source.contains("case .quitApp"))
        var clean = ExplainTurn()
        hold(&clean, transcript: "quit FixtureApp", screen: readyScreen())
        #expect(clean.closedApps == ["FixtureApp"])
        #expect(clean.approval == .none)

        var guarded = ExplainTurn()
        hold(&guarded, transcript: "close FixtureApp", screen: readyScreen(unsaved: ["FixtureApp"]))
        #expect(guarded.closedApps.isEmpty)
        #expect(guarded.approval == .close("FixtureApp"))
        guarded.handle(.approvalAllowed, screen: readyScreen(unsaved: ["FixtureApp"]), parse: fixtureParse)
        #expect(guarded.closedApps == ["FixtureApp"])
    }

    @Test func holdThenExplainThisSpeaksWithNumberedMarks() {
        var turn = ExplainTurn()
        hold(&turn, transcript: "explain this", screen: readyScreen())
        #expect(!turn.speech.isEmpty)
        #expect(turn.overlay.marks.map(\.number) == [1, 2])
        #expect(turn.overlay.marks.allSatisfy(\.relevant))
    }

    @Test func describeTheScreenSpeaksAndNumbersEachNamedItem() {
        var turn = ExplainTurn()
        hold(&turn, transcript: "describe what's on my screen", screen: readyScreen())
        #expect(turn.overlay.marks.map(\.name) == ["Save", "Export", "Close"])
        #expect(turn.overlay.marks.map(\.number) == [1, 2, 3])
        #expect(!turn.speech.isEmpty)
    }

    @Test func speechCallsOutTheMatchingMarkNumber() {
        var turn = ExplainTurn()
        let screen = readyScreen()
        hold(&turn, transcript: "describe what's on my screen", screen: screen)
        turn.handle(.phrase(id: "2", at: 2), screen: screen, parse: fixtureParse)
        let called = turn.overlay.marks.filter(\.calledOut)
        #expect(called.map(\.number) == [2])
        #expect(called.map(\.name) == ["Export"])
        #expect(turn.overlay.marks.count == 3)
        #expect(turn.announcements.contains("Mark 2, Export"))
    }

    @Test func aDescriptionThatNamesNothingDrawsNoMarks() {
        var turn = ExplainTurn()
        var screen = readyScreen()
        screen.controls = []
        hold(&turn, transcript: "describe what's on my screen", screen: screen)
        #expect(turn.overlay.marks.isEmpty)
        #expect(turn.speech.contains("nothing"))
    }

    @Test func showWhereToClickFliesThePointerAndHighlightsWhileNamed() {
        var turn = ExplainTurn()
        let screen = readyScreen()
        hold(&turn, transcript: "show me where to click to Export", screen: screen)
        #expect(turn.overlay.pointer?.motion == .fly)
        #expect(turn.overlay.pointer?.highlighted == true)
        #expect(turn.overlay.pointer?.frame == ExplainFrame(x: 40, y: 60, width: 90, height: 24))
        #expect(turn.didClick == false)
    }

    @Test func reduceMotionFadesTheHighlightInsteadOfFlying() {
        var turn = ExplainTurn()
        let screen = readyScreen(reduceMotion: true)
        turn.handle(.rightOptionDown(at: 0), screen: screen, parse: fixtureParse)
        turn.handle(.confirm(at: 0.25), screen: screen, parse: fixtureParse)
        #expect(turn.phase == .holding)
        turn.handle(.rightOptionUp(at: 1, transcript: "show me where to click to Export"), screen: screen, parse: fixtureParse)
        #expect(turn.overlay.pointer?.motion == .fade)
        #expect(turn.overlay.pointer?.highlighted == true)
        #expect(turn.didClick == false)
    }

    @Test func anUnseenControlDoesNotFlyAndDoesNotClick() {
        var turn = ExplainTurn()
        hold(&turn, transcript: "show me where to click to Missing", screen: readyScreen())
        #expect(turn.overlay.pointer?.frame == nil)
        #expect(turn.didClick == false)
        #expect(turn.speech.contains("cannot see"))
    }

    @Test func aWalkShowsOnlyTheCurrentStep() {
        var turn = ExplainTurn()
        hold(&turn, transcript: "walk me through export", screen: readyScreen())
        #expect(turn.visibleStepNames == ["Save"])
        #expect(turn.overlay.marks.map(\.name) == ["Save"])
    }

    @Test func aTapOrAFinishedStepAdvancesTheWalk() {
        var turn = ExplainTurn()
        let screen = readyScreen()
        hold(&turn, transcript: "walk me through export", screen: screen)
        turn.handle(.rightOptionDown(at: 3), screen: screen, parse: fixtureParse)
        turn.handle(.rightOptionUp(at: 3.05, transcript: ""), screen: screen, parse: fixtureParse)
        #expect(turn.phase != .holding)
        #expect(turn.openTurns == 1)
        #expect(turn.visibleStepNames == ["Export"])
        turn.handle(.stepFinished, screen: screen, parse: fixtureParse)
        #expect(turn.visibleStepNames == ["Close"])
    }

    @Test func escapeOrTheLastStepEndsTheWalk() {
        var escaped = ExplainTurn()
        let screen = readyScreen()
        hold(&escaped, transcript: "walk me through export", screen: screen)
        escaped.handle(.escape, screen: screen, parse: fixtureParse)
        #expect(escaped.phase == .idle)
        #expect(escaped.overlay.isUp == false)
        #expect(escaped.visibleStepNames.isEmpty)

        var finished = ExplainTurn()
        hold(&finished, transcript: "walk me through export", screen: screen)
        finished.handle(.stepFinished, screen: screen, parse: fixtureParse)
        finished.handle(.stepFinished, screen: screen, parse: fixtureParse)
        finished.handle(.stepFinished, screen: screen, parse: fixtureParse)
        #expect(finished.phase == .idle)
        #expect(finished.overlay.isUp == false)
        #expect(finished.visibleStepNames.isEmpty)
    }

    @Test func anEmptyWalkDoesNotOpenAResultOverlay() {
        var turn = ExplainTurn()
        var screen = readyScreen()
        screen.controls = []
        hold(&turn, transcript: "walk me through export", screen: screen)
        #expect(turn.overlay.isUp == false)
        #expect(turn.phase == .idle)
    }

    @Test func theLatencyClocksMatchTheSpec() {
        var turn = ExplainTurn()
        let screen = readyScreen()
        turn.handle(.rightOptionDown(at: 0), screen: screen, parse: fixtureParse)
        turn.handle(.confirm(at: 0.25), screen: screen, parse: fixtureParse)
        turn.handle(.rightOptionUp(at: 10, transcript: "show me where to click to Export"), screen: screen, parse: fixtureParse)
        turn.handle(.firstAudio(at: 10.4), screen: screen, parse: fixtureParse)
        turn.handle(.phrase(id: "2", at: 11), screen: screen, parse: fixtureParse)
        #expect(turn.clocks.releaseAt == 10)
        #expect(turn.clocks.firstAudioInterval == 0.4)
        #expect(turn.clocks.pointerInterval != nil)
        #expect(turn.clocks.measuredMedian == nil)
        #expect(turn.clocks.fastActionInterval != nil)
    }

    @Test func rightCommandHoldStillDictatesAndItsTapDoesNotExplain() {
        var held = ExplainTurn()
        let screen = readyScreen()
        held.handle(.rightCommandDown, screen: screen, parse: fixtureParse)
        held.handle(.rightCommandUp(held: 0.4), screen: screen, parse: fixtureParse)
        #expect(held.dictationHolds == 1)
        #expect(held.dictationSends == 1)
        #expect(held.openTurns == 0)
        #expect(held.phase == .idle)

        var tapped = ExplainTurn()
        tapped.handle(.rightCommandDown, screen: screen, parse: fixtureParse)
        tapped.handle(.rightCommandUp(held: 0.05), screen: screen, parse: fixtureParse)
        #expect(tapped.dictationSends == 0)
        #expect(tapped.openTurns == 0)
        #expect(tapped.overlay.isUp == false)
    }

    @Test func loadingDoesNotProcessAndErrorRecoversOnTheNextHold() {
        var turn = ExplainTurn()
        var screen = readyScreen(engineReady: false)
        turn.handle(.rightOptionDown(at: 0), screen: screen, parse: fixtureParse)
        turn.handle(.confirm(at: 0.25), screen: screen, parse: fixtureParse)
        #expect(turn.phase == .loading)
        #expect(turn.overlay.capturedRequest == false)
        turn.handle(.rightOptionUp(at: 1, transcript: "explain this"), screen: screen, parse: fixtureParse)
        #expect(turn.processedTranscripts.isEmpty)

        screen.engineReady = true
        turn.handle(.rightOptionDown(at: 2), screen: screen, parse: fixtureParse)
        turn.handle(.confirm(at: 2.25), screen: screen, parse: fixtureParse)
        #expect(turn.phase == .holding)
        turn.handle(.engineFailed("the speech engine stopped"), screen: screen, parse: fixtureParse)
        #expect(turn.phase == .error("the speech engine stopped"))
        #expect(turn.overlay.isUp == false)
        #expect(turn.processedTranscripts.isEmpty)
        #expect(turn.announcements.contains("the speech engine stopped"))

        turn.handle(.rightOptionDown(at: 4), screen: screen, parse: fixtureParse)
        #expect(turn.phase == .recovery)
        turn.handle(.confirm(at: 4.25), screen: screen, parse: fixtureParse)
        #expect(turn.phase == .holding)
        #expect(turn.processedTranscripts.isEmpty)
    }

    @Test func aSecondDownDoesNotOpenASecondTurn() {
        var turn = ExplainTurn()
        let screen = readyScreen()
        turn.handle(.rightOptionDown(at: 0), screen: screen, parse: fixtureParse)
        turn.handle(.confirm(at: 0.25), screen: screen, parse: fixtureParse)
        turn.handle(.rightOptionDown(at: 0.4), screen: screen, parse: fixtureParse)
        #expect(turn.openTurns == 1)
        #expect(turn.overlay.windowCount == 1)
    }

    private func bridgeSource() throws -> String {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("../../Sources/ZeusCore/Explain/ExplainFastIntentBridge.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
