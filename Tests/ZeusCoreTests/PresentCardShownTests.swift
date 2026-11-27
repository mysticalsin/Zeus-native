import Testing
@testable import ZeusCore

@Suite struct PresentCardShownTests {
    @Test func aStepsCardIsSpokenAndShown() {
        let card = PresentCard(kind: .steps, title: "Export", lines: ["Open File", "Pick format"])
        let shown = card.shown()
        #expect(shown?.spoken == "Export. Open File. Pick format.")
        #expect(shown?.bolt == "Export")
        #expect(shown?.spoken != shown?.bolt)
        #expect(PointerGuideCaptionSplit.boltText(shown?.bolt ?? "") == shown?.bolt)
    }

    @Test func aStepsCardIsBuiltOneStepAtATime() {
        let card = PresentCard(kind: .steps, title: "Export", lines: ["Open File", "Pick format"])
        let beats = card.beats()
        #expect(beats.map(\.spoken) == ["Export.", "Open File.", "Pick format."])
        #expect(beats.map(\.bolt) == ["Export", "Open File", "Pick format"])
        #expect(beats.allSatisfy { PointerGuideCaptionSplit.boltText($0.bolt) == $0.bolt })
        #expect(PresentCard(kind: .note, title: "  ", lines: [" ", ""]).beats().isEmpty)
    }

    @Test func aLongCardKeepsTheShortBolt() {
        let card = PresentCard(kind: .steps, title: "Share this window",
                               lines: ["Click the green button in the toolbar", "Choose the window"])
        let shown = card.shown()
        #expect(shown?.bolt == "Share this window")
        #expect(PointerGuideCaptionSplit.boltText(shown?.spoken ?? "") == nil)
    }

    @Test func aTitleThatCannotFitUsesTheShortBolt() {
        let title = String(repeating: "a", count: 50)
        let card = PresentCard(kind: .note, title: title, lines: [])
        let shown = card.shown()
        #expect(shown?.bolt == "Here")
        #expect(shown?.spoken == title + ".")
    }

    @Test func aCardWithNoWordsIsNotShown() {
        let card = PresentCard(kind: .list, title: "  ", lines: ["", " "])
        #expect(card.shown() == nil)
    }
}
