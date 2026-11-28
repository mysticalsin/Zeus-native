import Testing
@testable import ZeusCore

struct HeatDrawTests {
    private func cards(_ plan: HeatDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func thePageWordIsTheSecondCard() {
        let hot = HeatDraw.plan(word: "Too hot")
        #expect(cards(hot) == ["Heat", "Too hot"])
        #expect(HeatAsk.line(word: "Too hot") == "The Mac is too hot.")
        #expect(hot.boltCaption(at: 0) == "Heat")
        #expect(hot.boltCaption(at: ExplainBeatSchedule.gap) == "Too hot")
        #expect(hot.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(HeatAsk.line(word: "Cool") == "The Mac is cool.")
        #expect(HeatAsk.line(word: "Warm") == "The Mac is warm.")
        #expect(HeatAsk.line(word: "Hot") == "The Mac is hot.")
        #expect(cards(HeatDraw.plan(word: "Banana")) == ["Heat", "Can't"])
        #expect(HeatAsk.line(word: "") == "I can't read the heat.")
    }

    @Test func theLidAndTheWeatherStayOffThisAsk() {
        #expect(HeatAsk.matches("how's the heat"))
        #expect(HeatAsk.matches("Hey Zeus, is the Mac hot?"))
        #expect(!HeatAsk.matches("how's the lid"))
        #expect(!HeatAsk.matches("what's the weather"))
        #expect(!HeatAsk.matches("what's my battery"))
        #expect(!HeatAsk.matches("keep awake"))
        #expect(!HeatAsk.matches("how many chats"))
    }
}
