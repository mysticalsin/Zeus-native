import Testing
@testable import ZeusCore

struct NotchPlaceDrawTests {
    private func cards(_ plan: NotchPlaceDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theMenuTitleIsTheSecondCard() {
        let builtIn = NotchPlaceDraw.plan(word: "Built-in display")
        #expect(cards(builtIn) == ["Notch", "Built-in display"])
        #expect(NotchPlaceAsk.line(word: "Built-in display") == "The notch is on the built-in display.")
        #expect(builtIn.boltCaption(at: 0) == "Notch")
        #expect(builtIn.boltCaption(at: ExplainBeatSchedule.gap) == "Built-in display")
        #expect(builtIn.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(NotchPlaceAsk.line(word: "Display with the pointer") == "The notch follows the pointer.")
        #expect(NotchPlaceAsk.line(word: "All displays") == "The notch is on every display.")
        #expect(cards(NotchPlaceDraw.plan(word: "Banana")) == ["Notch", "Can't"])
        #expect(NotchPlaceAsk.line(word: "") == "I can't read where the notch is.")
    }

    @Test func theDisplayCountAndTheKeyboardStayOffThisAsk() {
        #expect(NotchPlaceAsk.matches("where's the notch"))
        #expect(NotchPlaceAsk.matches("Hey Zeus, which screen is the notch on?"))
        #expect(NotchPlaceAsk.matches("how's the notch"))
        #expect(!NotchPlaceAsk.matches("which screen"))
        #expect(!NotchPlaceAsk.matches("how many screens"))
        #expect(!NotchPlaceAsk.matches("where's my keyboard"))
        #expect(!NotchPlaceAsk.matches("can you drive"))
        #expect(!NotchPlaceAsk.matches("can you see the screen"))
    }
}
