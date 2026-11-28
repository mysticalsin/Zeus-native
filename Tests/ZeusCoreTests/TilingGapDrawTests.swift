import Testing
@testable import ZeusCore

struct TilingGapDrawTests {
    private func cards(_ plan: TilingGapDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallUsesEightAndFifty() {
        let usual = TilingGapDraw.plan(between: "8", edge: "8", split: "50")
        #expect(cards(usual) == ["Gaps", "Between: 8", "Edge: 8", "Split: 50%"])
        #expect(TilingGapAsk.line(between: "8", edge: "8", split: "50") == "Tiled windows sit 8 points apart, 8 points from the screen edge, and a new window leaves 50 percent.")
        #expect(usual.boltCaption(at: 0) == "Gaps")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Split: 50%")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(TilingGapAsk.line(between: "0", edge: "64", split: "30") == "Tiled windows sit 0 points apart, 64 points from the screen edge, and a new window leaves 30 percent.")
        #expect(cards(TilingGapDraw.plan(between: "16", edge: "12", split: "70")) == ["Gaps", "Between: 16", "Edge: 12", "Split: 70%"])
        #expect(cards(TilingGapDraw.plan(between: "65", edge: "8", split: "50")) == ["Gaps", "Can't"])
        #expect(TilingGapAsk.line(between: "08", edge: "8", split: "50") == "I can't read the tiling gaps.")
    }

    @Test func theTilingSwitchStaysOffThisAsk() {
        #expect(TilingGapAsk.matches("how are the tiling gaps"))
        #expect(TilingGapAsk.matches("Hey Zeus, what is the default split?"))
        #expect(TilingGapAsk.matches("tiling gap settings"))
        #expect(!TilingGapAsk.matches("how is tiling set"))
        #expect(!TilingGapAsk.matches("how is tiling"))
        #expect(!TilingGapAsk.matches("is tiling on"))
        #expect(!TilingGapAsk.matches("how is the halo measured"))
    }
}
