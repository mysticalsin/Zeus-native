import Testing
@testable import ZeusCore

struct PointerBuddyDrawTests {
    private func cards(_ plan: PointerBuddyDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theMenuTitleIsTheSecondCard() {
        let called = PointerBuddyDraw.plan(word: "When I call him")
        #expect(cards(called) == ["Pointer", "When I call him"])
        #expect(PointerBuddyAsk.line(word: "When I call him") == "Zeus appears when you call him.")
        #expect(called.boltCaption(at: 0) == "Pointer")
        #expect(called.boltCaption(at: ExplainBeatSchedule.gap) == "When I call him")
        #expect(called.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(PointerBuddyAsk.line(word: "Always") == "Zeus stays beside the pointer.")
        #expect(PointerBuddyAsk.line(word: "Never") == "Zeus stays off the pointer.")
        #expect(cards(PointerBuddyDraw.plan(word: "Banana")) == ["Pointer", "Can't"])
        #expect(PointerBuddyAsk.line(word: "") == "I can't read when Zeus appears.")
    }

    @Test func pointingKeysAndTheCardStyleStayOffThisAsk() {
        #expect(PointerBuddyAsk.matches("when do you show up"))
        #expect(PointerBuddyAsk.matches("Hey Zeus, when's zeus beside the pointer?"))
        #expect(PointerBuddyAsk.matches("how's the pointer buddy"))
        #expect(!PointerBuddyAsk.matches("what's the pointing key"))
        #expect(!PointerBuddyAsk.matches("what's the card style"))
        #expect(!PointerBuddyAsk.matches("where's the notch"))
        #expect(!PointerBuddyAsk.matches("is Hey Zeus on"))
    }
}
