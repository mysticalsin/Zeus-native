import Testing
@testable import ZeusCore

struct ScreenCountDrawTests {
    private func cards(_ plan: ScreenCountDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func oneScreenDrawsTheNameThenTheCount() {
        let plan = ScreenCountDraw.plan(count: 1, name: "Built-in Retina Display")
        #expect(plan.map(cards) == ["Screens", "Built-in Retina Display", "1"])
        #expect(ScreenCountAsk.line(count: 1, name: "Built-in Retina Display") == "You have 1 screen, Built-in Retina Display.")
        #expect(plan?.boltCaption(at: 0) == "Screens")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "Built-in Retina Display")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "1")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(ScreenCountDraw.plan(count: 0, name: "Built-in") == nil)
        #expect(cards(ScreenCountDraw.unseen()) == ["Screens", "Can't"])
        #expect(ScreenCountAsk.unseen == "I can't see a screen.")
    }

    @Test func severalScreensNameTheOneInUse() {
        let plan = ScreenCountDraw.plan(count: 2, name: "LG UltraFine")
        #expect(plan.map(cards) == ["Screens", "2", "LG UltraFine"])
        #expect(ScreenCountAsk.line(count: 2, name: "LG UltraFine") == "You have 2 screens. This one is LG UltraFine.")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "2")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "LG UltraFine")
        #expect(ScreenCountDraw.plan(count: 1, name: "  ").map(cards) == ["Screens", "1"])
        #expect(ScreenCountAsk.matches("how many screens"))
        #expect(ScreenCountAsk.matches("Hey Zeus, which display?"))
        #expect(ScreenCountAsk.matches("what screen is this"))
        #expect(!ScreenCountAsk.matches("is tiling on"))
        #expect(!ScreenCountAsk.matches("is dark mode on"))
        #expect(!ScreenCountAsk.matches("what's in front"))
        #expect(!ScreenCountAsk.matches("are you recording"))
    }
}
