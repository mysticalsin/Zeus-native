import Testing
@testable import ZeusCore

struct ResearchAskDrawTests {
    @Test func anEmptyResearchAskShowsAsk() throws {
        let plan = try #require(ResearchAskDraw.from(line: "What should I look into?"))
        func cards(_ plan: ResearchAskDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Research", "Ask"])
        #expect(plan.boltCaption(at: 0) == "Research")
        #expect(plan.boltCaption(at: 100) == "Ask")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aSavedReportAndAConnectedAIAreNotThisAsk() {
        #expect(ResearchAskDraw.from(line: "") == nil)
        #expect(ResearchAskDraw.from(line: "Done. The report is saved.") == nil)
        #expect(ResearchAskDraw.from(line: "Looking into tides.") == nil)
        #expect(ResearchAskDraw.from(line: "no AI is connected. Connect one in Settings, Integrations.") == nil)
    }
}
