import Testing
@testable import ZeusCore

struct PointRouteDrawTests {
    private func cards(_ plan: PointRouteDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallAsksAutoWithoutFnControl() {
        let usual = PointRouteDraw.plan(who: "Auto", fn: "Off")
        #expect(cards(usual) == ["Route", "Who: Auto", "Fn: Off"])
        #expect(PointRouteAsk.line(who: "Auto", fn: "Off") == "Pointing uses Auto, and Fn Control dictation is off.")
        #expect(usual.boltCaption(at: 0) == "Route")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Fn: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(PointRouteAsk.line(who: "Anthropic + ElevenLabs", fn: "On") == "Pointing uses Anthropic and ElevenLabs, and Fn Control dictation is on.")
        #expect(PointRouteAsk.line(who: "OpenAI", fn: "Off") == "Pointing uses OpenAI, and Fn Control dictation is off.")
        #expect(PointRouteAsk.line(who: "Zeus setup", fn: "On") == "Pointing uses the Zeus setup, and Fn Control dictation is on.")
        #expect(cards(PointRouteDraw.plan(who: "Claude", fn: "Off")) == ["Route", "Can't"])
        #expect(PointRouteAsk.line(who: "Auto", fn: "Maybe") == "I can't read who pointing asks.")
    }

    @Test func theTrailStaysOffThisAsk() {
        #expect(PointRouteAsk.matches("which pointing provider"))
        #expect(PointRouteAsk.matches("Hey Zeus, does pointing use fn control?"))
        #expect(PointRouteAsk.matches("who answers a point"))
        #expect(!PointRouteAsk.matches("who answers"))
        #expect(!PointRouteAsk.matches("how is the pointing trail set"))
        #expect(!PointRouteAsk.matches("which pointing keys"))
        #expect(!PointRouteAsk.matches("how big is the drawn notch"))
    }
}
