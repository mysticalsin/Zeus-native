import Testing
@testable import ZeusCore

struct ShelfStackDrawTests {
    private func cards(_ plan: ShelfStackDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func verifiedFilesAndStacks() {
        let usual = ShelfStackDraw.plan(verified: "0", stacks: "0")
        #expect(cards(usual) == ["Stacks", "Verified: 0", "Stacks: 0"])
        #expect(ShelfStackAsk.line(verified: "0", stacks: "0") == "No shelf files are verified, and there are no stacks.")
        #expect(usual.boltCaption(at: 0) == "Stacks")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Stacks: 0")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ShelfStackAsk.line(verified: "1", stacks: "0") == "1 shelf file is verified, and there are no stacks.")
        #expect(ShelfStackAsk.line(verified: "3", stacks: "1") == "3 shelf files are verified, and there is 1 stack.")
        #expect(cards(ShelfStackDraw.plan(verified: "1000", stacks: "0")) == ["Stacks", "Can't"])
        #expect(ShelfStackAsk.line(verified: "0", stacks: "many") == "I can't read the shelf stacks.")
    }

    @Test func theFileNamesStayOffThisAsk() {
        #expect(ShelfStackAsk.matches("how many shelf files are verified"))
        #expect(ShelfStackAsk.matches("Hey Zeus, how many shelf stacks are there?"))
        #expect(ShelfStackAsk.matches("are any shelf files verified"))
        #expect(!ShelfStackAsk.matches("what is on the shelf"))
        #expect(!ShelfStackAsk.matches("how many files are on the shelf"))
        #expect(!ShelfStackAsk.matches("how is fling set"))
        #expect(!ShelfStackAsk.matches("is the calendar on today"))
    }
}
