import Testing
@testable import ZeusCore

struct AskFinishDrawTests {
    private func cards(_ plan: AskFinishDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func permissionRequestsAlwaysShow() {
        let usual = AskFinishDraw.plan(asks: "Always", done: "Off")
        #expect(cards(usual) == ["Wait", "Asks: Always", "Done: Off"])
        #expect(AskFinishAsk.line(asks: "Always", done: "Off") == "Permission requests always show, and a finished agent does not send a banner.")
        #expect(usual.boltCaption(at: 0) == "Wait")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Done: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(AskFinishAsk.line(asks: "Always", done: "On") == "Permission requests always show, and a finished agent sends a banner.")
        #expect(cards(AskFinishDraw.plan(asks: "Sometimes", done: "Off")) == ["Wait", "Can't"])
        #expect(AskFinishAsk.line(asks: "Always", done: "Maybe") == "I can't read permission and finish notices.")
    }

    @Test func errorNoticesStayOffThisAsk() {
        #expect(AskFinishAsk.matches("do permission requests always show"))
        #expect(AskFinishAsk.matches("Hey Zeus, does a finished agent banner?"))
        #expect(AskFinishAsk.matches("are finished task banners on"))
        #expect(!AskFinishAsk.matches("how is agent notices set"))
        #expect(!AskFinishAsk.matches("are system notifications on"))
        #expect(!AskFinishAsk.matches("how are finished agents shown"))
        #expect(!AskFinishAsk.matches("how do question answers go back"))
    }
}
