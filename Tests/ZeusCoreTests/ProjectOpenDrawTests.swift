import Testing
@testable import ZeusCore

struct ProjectOpenDrawTests {
    @Test func anOpenShowsTheProjectThenTheApp() throws {
        let plan = try #require(ProjectOpenDraw.plan(name: "Zeus", app: "Cursor"))
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Open", "Zeus", "Cursor"])
        #expect(plan.boltCaption(at: 0) == "Open")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "Zeus")
        #expect(plan.boltCaption(at: 100) == "Cursor")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankProjectOrAppIsNotDrawn() {
        #expect(ProjectOpenDraw.plan(name: "  ", app: "Cursor") == nil)
        #expect(ProjectOpenDraw.plan(name: "Zeus", app: "\n") == nil)
    }
}
