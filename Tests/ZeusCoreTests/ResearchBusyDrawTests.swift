import Testing
@testable import ZeusCore

struct ResearchBusyDrawTests {
    @Test func anOngoingResearchShowsStop() throws {
        let plan = try #require(ResearchBusyDraw.from(line: "I'm already researching something. Stop it first."))
        func cards(_ plan: ResearchBusyDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Research", "Stop"])
        #expect(plan.boltCaption(at: 0) == "Research")
        #expect(plan.boltCaption(at: 100) == "Stop")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aResearchQuestionAndAForgottenItemAreNotThisBusy() {
        #expect(ResearchBusyDraw.from(line: "") == nil)
        #expect(ResearchBusyDraw.from(line: "I'm already researching something. Stop it first") == nil)
        #expect(ResearchBusyDraw.from(line: "What should I look into?") == nil)
        #expect(ResearchBusyDraw.from(line: "I'm already driving. Press Esc to stop that first.") == nil)
        #expect(ResearchBusyDraw.from(line: "Forgot one item.") == nil)
        #expect(ResearchBusyDraw.from(line: "Done. The report is saved.") == nil)
    }
}
