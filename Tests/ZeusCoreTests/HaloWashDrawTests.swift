import Testing
@testable import ZeusCore

struct HaloWashDrawTests {
    private func cards(_ plan: HaloWashDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallMatchesTheWallpaperAndReachesTheEdges() {
        let usual = HaloWashDraw.plan(wallpaper: "On", edge: "On")
        #expect(cards(usual) == ["Wash", "Wallpaper: On", "Edge: On"])
        #expect(HaloWashAsk.line(wallpaper: "On", edge: "On") == "The halo matches the wallpaper, and the edge wave is on.")
        #expect(usual.boltCaption(at: 0) == "Wash")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Edge: On")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(HaloWashAsk.line(wallpaper: "Off", edge: "Off") == "The halo does not match the wallpaper, and the edge wave is off.")
        #expect(cards(HaloWashDraw.plan(wallpaper: "Off", edge: "On")) == ["Wash", "Wallpaper: Off", "Edge: On"])
        #expect(cards(HaloWashDraw.plan(wallpaper: "Maybe", edge: "On")) == ["Wash", "Can't"])
        #expect(HaloWashAsk.line(wallpaper: "On", edge: "Soon") == "I can't read how the halo meets the screen.")
    }

    @Test func theLightPictureStaysOffThisAsk() {
        #expect(HaloWashAsk.matches("does the halo match the wallpaper"))
        #expect(HaloWashAsk.matches("Hey Zeus, is the edge wave on?"))
        #expect(HaloWashAsk.matches("does light reach the screen edges"))
        #expect(!HaloWashAsk.matches("what is the halo"))
        #expect(!HaloWashAsk.matches("how is the halo arm"))
        #expect(!HaloWashAsk.matches("how is the halo entrance"))
        #expect(!HaloWashAsk.matches("how are arrival lights set"))
    }
}
