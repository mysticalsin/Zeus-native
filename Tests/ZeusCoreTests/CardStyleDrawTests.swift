import Testing
@testable import ZeusCore

struct CardStyleDrawTests {
    private func cards(_ plan: CardStyleDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func thePictureTitleIsTheSecondCard() {
        let glass = CardStyleDraw.plan(word: "Liquid Glass")
        #expect(cards(glass) == ["Look", "Liquid Glass"])
        #expect(CardStyleAsk.line(word: "Liquid Glass") == "The cards use Liquid Glass.")
        #expect(glass.boltCaption(at: 0) == "Look")
        #expect(glass.boltCaption(at: ExplainBeatSchedule.gap) == "Liquid Glass")
        #expect(glass.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(CardStyleAsk.line(word: "Physical") == "The cards use Physical.")
        #expect(CardStyleAsk.line(word: "Dashboard B") == "The cards use Dashboard B.")
        #expect(cards(CardStyleDraw.plan(word: "Banana")) == ["Look", "Can't"])
        #expect(CardStyleAsk.line(word: "") == "I can't read the card style.")
    }

    @Test func darkModeAndTheMusicSourceStayOffThisAsk() {
        #expect(CardStyleAsk.matches("what's the card style"))
        #expect(CardStyleAsk.matches("Hey Zeus, how's the look?"))
        #expect(CardStyleAsk.matches("card style"))
        #expect(!CardStyleAsk.matches("is dark mode on"))
        #expect(!CardStyleAsk.matches("where's the music from"))
        #expect(!CardStyleAsk.matches("who answers"))
        #expect(!CardStyleAsk.matches("what's the chat shortcut"))
    }
}
