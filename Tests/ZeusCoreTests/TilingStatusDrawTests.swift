import Testing
@testable import ZeusCore

struct TilingStatusDrawTests {
    private func cards(_ plan: TilingStatusDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func tilingOnDrawsOn() {
        let plan = TilingStatusDraw.plan(.on)
        #expect(cards(plan) == ["Tiling", "On"])
        #expect(TilingStatusAsk.line(.on) == "Tiling is on.")
        #expect(plan.boltCaption(at: 0) == "Tiling")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "On")
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func theOtherStatesStayOffDarkMode() {
        #expect(cards(TilingStatusDraw.plan(.off)) == ["Tiling", "Off"])
        #expect(TilingStatusAsk.line(.paused) == "Tiling is paused.")
        #expect(cards(TilingStatusDraw.plan(.access)) == ["Tiling", "Needs Accessibility"])
        #expect(TilingStatusAsk.line(.clash) == "Tiling has a key clash.")
        #expect(TilingStatusAsk.line(.keys) == "Tiling keys are unavailable.")
        #expect(TilingStatusAsk.matches("is tiling on"))
        #expect(TilingStatusAsk.matches("Hey Zeus, how's tiling?"))
        #expect(TilingStatusAsk.matches("tiling"))
        #expect(!TilingStatusAsk.matches("is dark mode on"))
        #expect(!TilingStatusAsk.matches("are you recording"))
        #expect(!TilingStatusAsk.matches("turn tiling on"))
        #expect(!TilingStatusAsk.matches("how many words today"))
    }
}
