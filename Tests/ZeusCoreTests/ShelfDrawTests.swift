import Testing
@testable import ZeusCore

struct ShelfDrawTests {
    private func cards(_ plan: ShelfDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func oneFileDrawsTheNameThenTheCount() {
        let plan = ShelfDraw.plan(count: 1, name: "Notes.pdf")
        #expect(plan.map(cards) == ["Shelf", "Notes.pdf", "1 file"])
        #expect(ShelfAsk.line(count: 1, name: "Notes.pdf") == "You have Notes.pdf on the shelf.")
        #expect(ShelfAsk.line(count: 1, name: "  ") == "You have 1 file on the shelf.")
        #expect(plan?.boltCaption(at: 0) == "Shelf")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "Notes.pdf")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "1 file")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(ShelfDraw.plan(count: 0, name: "Notes.pdf") == nil)
    }

    @Test func severalFilesDrawTheCountAndAnEmptyShelfIsNotASearch() {
        let plan = ShelfDraw.plan(count: 4, name: "Invoice.pdf")
        #expect(plan.map(cards) == ["Shelf", "4 files", "Invoice.pdf"])
        #expect(ShelfAsk.line(count: 4, name: "Invoice.pdf") == "You have 4 files on the shelf. The newest is Invoice.pdf.")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "4 files")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Invoice.pdf")
        #expect(cards(ShelfDraw.empty()) == ["Shelf", "None"])
        #expect(ShelfAsk.empty == "The shelf is empty.")
        #expect(ShelfAsk.matches("what's on my shelf"))
        #expect(ShelfAsk.matches("Hey Zeus, how many files on the shelf?"))
        #expect(ShelfAsk.matches("my shelf"))
        #expect(!ShelfAsk.matches("find the file named notes"))
        #expect(!ShelfAsk.matches("what's on my agenda"))
        #expect(!ShelfAsk.matches("how many to-dos"))
        #expect(!ShelfAsk.matches("how many notifications"))
        #expect(!ShelfAsk.matches("how many meetings"))
    }
}
