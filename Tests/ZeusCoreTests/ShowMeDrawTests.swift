import Testing
@testable import ZeusCore

struct ShowMeDrawTests {
    private func cards(_ plan: ShowMeDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallCirclesAndRunsSafeSteps() {
        let usual = ShowMeDraw.plan(show: "On", steps: "On")
        #expect(cards(usual) == ["Show", "Draw: On", "Steps: On"])
        #expect(ShowMeAsk.line(show: "On", steps: "On") == "Show me is on, and safe steps run without asking.")
        #expect(usual.boltCaption(at: 0) == "Show")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Steps: On")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ShowMeAsk.line(show: "Off", steps: "Off") == "Show me is off, and safe steps wait for a yes.")
        #expect(ShowMeAsk.line(show: "On", steps: "Off") == "Show me is on, and safe steps wait for a yes.")
        #expect(cards(ShowMeDraw.plan(show: "Yes", steps: "On")) == ["Show", "Can't"])
        #expect(ShowMeAsk.line(show: "On", steps: "Maybe") == "I can't read show me.")
    }

    @Test func drivingTheMacStaysOffThisAsk() {
        #expect(ShowMeAsk.matches("is show me on"))
        #expect(ShowMeAsk.matches("Hey Zeus, can I circle on the screen?"))
        #expect(ShowMeAsk.matches("do safe steps run on their own"))
        #expect(!ShowMeAsk.matches("when may zeus drive"))
        #expect(!ShowMeAsk.matches("how is drive"))
        #expect(!ShowMeAsk.matches("does talk draw on the screen"))
        #expect(!ShowMeAsk.matches("are visual explanations on"))
    }
}
