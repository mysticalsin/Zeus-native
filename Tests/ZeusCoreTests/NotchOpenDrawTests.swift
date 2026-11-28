import Testing
@testable import ZeusCore

struct NotchOpenDrawTests {
    private func cards(_ plan: NotchOpenDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theMenuTitleIsTheSecondCard() {
        let hover = NotchOpenDraw.plan(word: "Hover")
        #expect(cards(hover) == ["Open", "Hover"])
        #expect(NotchOpenAsk.line(word: "Hover") == "The notch opens when the pointer rests on it.")
        #expect(hover.boltCaption(at: 0) == "Open")
        #expect(hover.boltCaption(at: ExplainBeatSchedule.gap) == "Hover")
        #expect(hover.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(NotchOpenAsk.line(word: "Click") == "The notch opens when you click it.")
        #expect(cards(NotchOpenDraw.plan(word: "Banana")) == ["Open", "Can't"])
        #expect(NotchOpenAsk.line(word: "") == "I can't read how the notch opens.")
    }

    @Test func whereTheNotchShowsStaysOffThisAsk() {
        #expect(NotchOpenAsk.matches("how does the notch open"))
        #expect(NotchOpenAsk.matches("Hey Zeus, how's the notch open?"))
        #expect(NotchOpenAsk.matches("notch open"))
        #expect(!NotchOpenAsk.matches("where's the notch"))
        #expect(!NotchOpenAsk.matches("when do you show up"))
        #expect(!NotchOpenAsk.matches("what's the card style"))
        #expect(!NotchOpenAsk.matches("how's the pointer buddy"))
    }
}
