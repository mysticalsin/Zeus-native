import Testing
@testable import ZeusCore

struct ResearchStartDrawTests {
    @Test func aQuestionShowsTheTopicAndADeepAskAddsInDepth() throws {
        let quick = try #require(ResearchStartDraw.plan(topic: "tides", deep: false))
        let deep = try #require(ResearchStartDraw.plan(topic: "how tides work", deep: true))
        func cards(_ plan: ResearchStartDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(quick) == ["Research", "tides"])
        #expect(cards(deep) == ["Research", "how tides work", "In depth"])
        #expect(quick.boltCaption(at: 0) == "Research")
        #expect(quick.boltCaption(at: 100) == "tides")
        #expect(deep.boltCaption(at: 100) == "In depth")
        #expect(quick.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(quick.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankTopicIsNotDrawn() {
        #expect(ResearchStartDraw.plan(topic: "  ", deep: true) == nil)
        #expect(ResearchStartDraw.plan(topic: "\n", deep: false) == nil)
    }
}
