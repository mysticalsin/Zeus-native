import Testing
@testable import ZeusCore

struct ClipboardFilterDrawTests {
    private func cards(_ plan: ClipboardFilterDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theChipAndThePins() {
        let usual = ClipboardFilterDraw.plan(chip: "All", pins: "0")
        #expect(cards(usual) == ["Shown", "Chip: All", "Pins: 0"])
        #expect(ClipboardFilterAsk.line(chip: "All", pins: "0") == "The clipboard is showing All, and no clips are pinned.")
        #expect(usual.boltCaption(at: 0) == "Shown")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Pins: 0")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ClipboardFilterAsk.line(chip: "Text", pins: "1") == "The clipboard is showing Text, and 1 clip is pinned.")
        #expect(ClipboardFilterAsk.line(chip: "Links", pins: "3") == "The clipboard is showing Links, and 3 clips are pinned.")
        #expect(cards(ClipboardFilterDraw.plan(chip: "Audio", pins: "0")) == ["Shown", "Can't"])
        #expect(ClipboardFilterAsk.line(chip: "All", pins: "1000") == "I can't read the clipboard filter.")
    }

    @Test func theClipCountStaysOffThisAsk() {
        #expect(ClipboardFilterAsk.matches("which clips are showing"))
        #expect(ClipboardFilterAsk.matches("Hey Zeus, how many clips are pinned?"))
        #expect(ClipboardFilterAsk.matches("which clipboard chip"))
        #expect(!ClipboardFilterAsk.matches("how many clips"))
        #expect(!ClipboardFilterAsk.matches("what is on the clipboard"))
        #expect(!ClipboardFilterAsk.matches("which reminders are showing"))
        #expect(!ClipboardFilterAsk.matches("is shuffle on"))
    }
}
