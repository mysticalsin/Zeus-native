import Testing
@testable import ZeusCore

struct NoGoalDrawTests {
    @Test func aMissingGoalShowsMissing() throws {
        let plan = try #require(NoGoalDraw.from(line: "there was no goal."))
        func cards(_ plan: NoGoalDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Goal", "Missing"])
        #expect(plan.boltCaption(at: 0) == "Goal")
        #expect(plan.boltCaption(at: 100) == "Missing")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aSetupLineAndAnEmptyLineAreNotAMissingGoal() {
        #expect(NoGoalDraw.from(line: "") == nil)
        #expect(NoGoalDraw.from(line: "the separate browser isn't set up yet. Open Settings, Features.") == nil)
        #expect(NoGoalDraw.from(line: "the browser agent is off. Turn it on in Settings.") == nil)
        #expect(NoGoalDraw.from(line: "Zeus isn't ready yet.") == nil)
    }
}
