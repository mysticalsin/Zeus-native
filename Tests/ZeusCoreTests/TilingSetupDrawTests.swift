import Testing
@testable import ZeusCore

struct TilingSetupDrawTests {
    private func cards(_ plan: TilingSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func workKeysAndRingFollowArrange() {
        let usual = TilingSetupDraw.plan(work: "Off", keys: "Control-Option-Command", ring: "On")
        #expect(cards(usual) == ["Arrange", "Work: Off", "Keys: Control-Option-Command", "Ring: On"])
        #expect(TilingSetupAsk.line(work: "Off", keys: "Control-Option-Command", ring: "On") == "Tiling is off, the keys are Control-Option-Command, and the focus ring is on.")
        #expect(usual.boltCaption(at: 0) == "Arrange")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Ring: On")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(TilingSetupAsk.line(work: "On", keys: "Option-Command", ring: "Off") == "Tiling is on, the keys are Option-Command, and the focus ring is off.")
        #expect(cards(TilingSetupDraw.plan(work: "On", keys: "Control-Option", ring: "On")) == ["Arrange", "Work: On", "Keys: Control-Option", "Ring: On"])
        #expect(cards(TilingSetupDraw.plan(work: "On", keys: "Fn", ring: "On")) == ["Arrange", "Can't"])
        #expect(TilingSetupAsk.line(work: "Maybe", keys: "Control-Option", ring: "On") == "I can't read how tiling is set.")
    }

    @Test func theLiveStatusStaysOffThisAsk() {
        #expect(TilingSetupAsk.matches("how's tiling set"))
        #expect(TilingSetupAsk.matches("Hey Zeus, which tiling keys?"))
        #expect(TilingSetupAsk.matches("tiling settings"))
        #expect(!TilingSetupAsk.matches("how's tiling"))
        #expect(!TilingSetupAsk.matches("is tiling on"))
        #expect(!TilingSetupAsk.matches("what's the pointing key"))
        #expect(!TilingSetupAsk.matches("how's fling set"))
    }
}
