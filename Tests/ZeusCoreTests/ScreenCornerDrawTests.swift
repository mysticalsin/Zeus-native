import Testing
@testable import ZeusCore

struct ScreenCornerDrawTests {
    private func cards(_ plan: ScreenCornerDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func roundingAndSizeFollowCorners() {
        let usual = ScreenCornerDraw.plan(round: "Off", size: "Medium")
        #expect(cards(usual) == ["Corners", "Round: Off", "Size: Medium"])
        #expect(ScreenCornerAsk.line(round: "Off", size: "Medium") == "Bottom corners are off, and the size is Medium.")
        #expect(usual.boltCaption(at: 0) == "Corners")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Size: Medium")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ScreenCornerAsk.line(round: "On", size: "Large") == "Bottom corners are on, and the size is Large.")
        #expect(cards(ScreenCornerDraw.plan(round: "On", size: "Small")) == ["Corners", "Round: On", "Size: Small"])
        #expect(cards(ScreenCornerDraw.plan(round: "On", size: "Huge")) == ["Corners", "Can't"])
        #expect(ScreenCornerAsk.line(round: "Maybe", size: "Medium") == "I can't read the screen corners.")
    }

    @Test func theScreenCountAndTheHomeFrameStayOffThisAsk() {
        #expect(ScreenCornerAsk.matches("how's the screen corners"))
        #expect(ScreenCornerAsk.matches("Hey Zeus, what's the corner size?"))
        #expect(ScreenCornerAsk.matches("screen corner settings"))
        #expect(!ScreenCornerAsk.matches("how many screens"))
        #expect(!ScreenCornerAsk.matches("can you see the screen"))
        #expect(!ScreenCornerAsk.matches("how's the home frame"))
    }
}
