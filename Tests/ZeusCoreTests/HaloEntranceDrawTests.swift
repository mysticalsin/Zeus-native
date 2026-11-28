import Testing
@testable import ZeusCore

struct HaloEntranceDrawTests {
    private func cards(_ plan: HaloEntranceDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theMoveFollowsEntrance() {
        let usual = HaloEntranceDraw.plan(move: "Sweep")
        #expect(cards(usual) == ["Entrance", "Move: Sweep"])
        #expect(HaloEntranceAsk.line(move: "Sweep") == "The halo entrance is Sweep.")
        #expect(usual.boltCaption(at: 0) == "Entrance")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap + 0.001) == "Move: Sweep")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap + 0.001) == TalkDraw.Point(x: 920, y: 180))
        #expect(HaloEntranceAsk.line(move: "Trace (sleek)") == "The halo entrance is Trace (sleek).")
        #expect(HaloEntranceAsk.line(move: "Big Bang") == "The halo entrance is Big Bang.")
        #expect(cards(HaloEntranceDraw.plan(move: "Shimmer")) == ["Entrance", "Move: Shimmer"])
        #expect(cards(HaloEntranceDraw.plan(move: "Spin")) == ["Entrance", "Can't"])
        #expect(HaloEntranceAsk.line(move: "Fade") == "I can't read the halo entrance.")
    }

    @Test func theHaloStyleStaysOffThisAsk() {
        #expect(HaloEntranceAsk.matches("what's the halo entrance"))
        #expect(HaloEntranceAsk.matches("Hey Zeus, which entrance animation?"))
        #expect(HaloEntranceAsk.matches("halo entrance settings"))
        #expect(!HaloEntranceAsk.matches("what's the halo"))
        #expect(!HaloEntranceAsk.matches("how's the halo"))
        #expect(!HaloEntranceAsk.matches("which halo"))
        #expect(!HaloEntranceAsk.matches("how's flick set"))
    }
}
