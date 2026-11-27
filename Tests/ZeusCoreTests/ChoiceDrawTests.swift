import Testing
@testable import ZeusCore

struct ChoiceDrawTests {
    @Test func aPairShowsBothNames() throws {
        let pair = try #require(ChoiceDraw.from(question: "Did you mean Notes or Notion?"))
        func cards(_ plan: ChoiceDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(pair) == ["Which", "Notes", "Notion"])
        #expect(pair.boltCaption(at: 0) == "Which")
        #expect(pair.boltCaption(at: ExplainBeatSchedule.gap) == "Notes")
        #expect(pair.boltCaption(at: 100) == "Notion")
        #expect(pair.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(pair.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankNameAndOtherQuestionsAreNotDrawn() {
        #expect(ChoiceDraw.from(question: "Did you mean  or Notion?") == nil)
        #expect(ChoiceDraw.from(question: "Did you mean Notes or ?") == nil)
        #expect(ChoiceDraw.from(question: "Did you mean Notes?") == nil)
        #expect(ChoiceDraw.from(question: "Did you mean Notes or Notion or Mail?") == nil)
        #expect(ChoiceDraw.from(question: "Open Safari") == nil)
        #expect(ChoiceDraw.plan(first: " ", second: "Notion") == nil)
    }
}
