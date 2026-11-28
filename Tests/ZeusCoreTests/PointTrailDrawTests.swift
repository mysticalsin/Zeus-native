import Testing
@testable import ZeusCore

struct PointTrailDrawTests {
    private func cards(_ plan: PointTrailDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallDrawsTheTrailAndSendsNothing() {
        let usual = PointTrailDraw.plan(point: "On", ink: "On", shot: "Off", type: "Off")
        #expect(cards(usual) == ["Trail", "Point: On", "Ink: On", "Shot: Off", "Type: Off"])
        #expect(PointTrailAsk.line(point: "On", ink: "On", shot: "Off", type: "Off") == "Pointing is on, the trail while held is on, screenshots stay off, and typed questions are off.")
        #expect(usual.boltCaption(at: 0) == "Trail")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Type: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(PointTrailAsk.line(point: "Off", ink: "Off", shot: "On", type: "On") == "Pointing is off, the trail while held is off, screenshots go with each question, and typed questions are on.")
        #expect(cards(PointTrailDraw.plan(point: "Yes", ink: "On", shot: "Off", type: "Off")) == ["Trail", "Can't"])
        #expect(PointTrailAsk.line(point: "Maybe", ink: "On", shot: "Off", type: "Off") == "I can't read how pointing draws.")
    }

    @Test func thePointingKeysStayOffThisAsk() {
        #expect(PointTrailAsk.matches("how is the pointing trail set"))
        #expect(PointTrailAsk.matches("Hey Zeus, does pointing draw while held?"))
        #expect(PointTrailAsk.matches("does pointing send a screenshot"))
        #expect(!PointTrailAsk.matches("how is pointing"))
        #expect(!PointTrailAsk.matches("which pointing keys"))
        #expect(!PointTrailAsk.matches("can you see the screen"))
        #expect(!PointTrailAsk.matches("how is narration set"))
    }
}
