import Testing
@testable import ZeusCore

struct AssistantMissDrawTests {
    @Test func anUnknownAssistantShowsItsName() throws {
        let plan = try #require(AssistantMissDraw.from(line: "No assistant called dust"))
        func cards(_ plan: AssistantMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Assistant", "dust"])
        #expect(plan.boltCaption(at: 0) == "Assistant")
        #expect(plan.boltCaption(at: 100) == "dust")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aMissingTabAndAClaudeToolAreNotThisAssistant() {
        #expect(AssistantMissDraw.from(line: "") == nil)
        #expect(AssistantMissDraw.from(line: "No assistant called") == nil)
        #expect(AssistantMissDraw.from(line: "No assistant called dust.") == nil)
        #expect(AssistantMissDraw.from(line: "I couldn't find that tab") == nil)
        #expect(AssistantMissDraw.from(line: "No active Chrome tab") == nil)
        #expect(AssistantMissDraw.from(line: "Chrome doesn't let extensions act on this page") == nil)
        #expect(AssistantMissDraw.from(line: "I can't find the claude command line tool.") == nil)
    }
}
