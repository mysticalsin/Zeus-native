import Testing
@testable import ZeusCore

struct HomeFrameDrawTests {
    private func cards(_ plan: HomeFrameDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theFrameAndFinishFollowFrame() {
        let usual = HomeFrameDraw.plan(frame: "Device", finish: "Same all")
        #expect(cards(usual) == ["Frame", "Home: Device", "Finish: Same all"])
        #expect(HomeFrameAsk.line(frame: "Device", finish: "Same all") == "The Home frame is Device, and the Physical finish is Same all.")
        #expect(usual.boltCaption(at: 0) == "Frame")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Finish: Same all")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(HomeFrameAsk.line(frame: "Borderless colour", finish: "Separate") == "The Home frame is Borderless colour, and the Physical finish is Separate.")
        #expect(cards(HomeFrameDraw.plan(frame: "Borderless", finish: "Same all")) == ["Frame", "Home: Borderless", "Finish: Same all"])
        #expect(cards(HomeFrameDraw.plan(frame: "Rounded", finish: "Same all")) == ["Frame", "Can't"])
        #expect(HomeFrameAsk.line(frame: "Device", finish: "Mixed") == "I can't read the Home frame.")
    }

    @Test func theCardPicturesAndTheWidgetStylesStayOffThisAsk() {
        #expect(HomeFrameAsk.matches("how's the home frame"))
        #expect(HomeFrameAsk.matches("Hey Zeus, what's the physical finish?"))
        #expect(HomeFrameAsk.matches("home frame settings"))
        #expect(!HomeFrameAsk.matches("what's the card style"))
        #expect(!HomeFrameAsk.matches("how's the look"))
        #expect(!HomeFrameAsk.matches("how's home styled"))
        #expect(!HomeFrameAsk.matches("how's the nudge set"))
    }
}
