import Testing
@testable import ZeusCore

struct FlingSetupDrawTests {
    private func cards(_ plan: FlingSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func workSeeAndSaveFollowFling() {
        let usual = FlingSetupDraw.plan(work: "Off", see: "Everyone nearby", save: "Downloads/Fling")
        #expect(cards(usual) == ["Fling", "Work: Off", "See: Everyone nearby", "Save: Downloads/Fling"])
        #expect(FlingSetupAsk.line(work: "Off", see: "Everyone nearby", save: "Downloads/Fling") == "Fling is off, shows Everyone nearby, and arrivals use Downloads/Fling.")
        #expect(usual.boltCaption(at: 0) == "Fling")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Save: Downloads/Fling")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(FlingSetupAsk.line(work: "On", see: "Paired only", save: "Clipboard") == "Fling is on, shows Paired only, and arrivals use Clipboard.")
        #expect(cards(FlingSetupDraw.plan(work: "Off", see: "Off", save: "Ask each time")) == ["Fling", "Work: Off", "See: Off", "Save: Ask each time"])
        #expect(cards(FlingSetupDraw.plan(work: "On", see: "Friends", save: "Downloads/Fling")) == ["Fling", "Can't"])
        #expect(FlingSetupAsk.line(work: "Maybe", see: "Everyone nearby", save: "Desktop") == "I can't read how Fling is set.")
    }

    @Test func theFilesOnTheShelfStayOffThisAsk() {
        #expect(FlingSetupAsk.matches("how's fling set"))
        #expect(FlingSetupAsk.matches("Hey Zeus, who can see this Mac?"))
        #expect(FlingSetupAsk.matches("fling settings"))
        #expect(!FlingSetupAsk.matches("what's on my shelf"))
        #expect(!FlingSetupAsk.matches("the shelf"))
        #expect(!FlingSetupAsk.matches("how's keep awake set"))
    }
}
