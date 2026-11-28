import Testing
@testable import ZeusCore

struct HaloMeasureDrawTests {
    private func cards(_ plan: HaloMeasureDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallSitsAtOneHundred() {
        let usual = HaloMeasureDraw.plan(strength: "100", speed: "100", thick: "100")
        #expect(cards(usual) == ["Measure", "Strength: 100", "Speed: 100", "Thick: 100"])
        #expect(HaloMeasureAsk.line(strength: "100", speed: "100", thick: "100") == "The entrance strength is 100, the speed is 100, and the light is 100 thick.")
        #expect(usual.boltCaption(at: 0) == "Measure")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Thick: 100")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(HaloMeasureAsk.line(strength: "50", speed: "200", thick: "200") == "The entrance strength is 50, the speed is 200, and the light is 200 thick.")
        #expect(cards(HaloMeasureDraw.plan(strength: "150", speed: "50", thick: "105")) == ["Measure", "Strength: 150", "Speed: 50", "Thick: 105"])
        #expect(cards(HaloMeasureDraw.plan(strength: "49", speed: "100", thick: "100")) == ["Measure", "Can't"])
        #expect(HaloMeasureAsk.line(strength: "100", speed: "060", thick: "100") == "I can't read the halo measures.")
    }

    @Test func theEntranceAnimationStaysOffThisAsk() {
        #expect(HaloMeasureAsk.matches("how strong is the entrance"))
        #expect(HaloMeasureAsk.matches("Hey Zeus, how thick is the halo?"))
        #expect(HaloMeasureAsk.matches("what is the entrance intensity"))
        #expect(!HaloMeasureAsk.matches("how is the halo entrance"))
        #expect(!HaloMeasureAsk.matches("what is the halo"))
        #expect(!HaloMeasureAsk.matches("does the halo match the wallpaper"))
        #expect(!HaloMeasureAsk.matches("is per-app sound on"))
    }
}
