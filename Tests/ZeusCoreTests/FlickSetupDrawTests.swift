import Testing
@testable import ZeusCore

struct FlickSetupDrawTests {
    private func cards(_ plan: FlickSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theSpeedFollowsFlick() {
        let usual = FlickSetupDraw.plan(speed: "Normal")
        #expect(cards(usual) == ["Flick", "Speed: Normal"])
        #expect(FlickSetupAsk.line(speed: "Normal") == "A flick toward a nearby Mac is Normal.")
        #expect(usual.boltCaption(at: 0) == "Flick")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap + 0.001) == "Speed: Normal")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap + 0.001) == TalkDraw.Point(x: 920, y: 180))
        #expect(FlickSetupAsk.line(speed: "Low") == "A flick toward a nearby Mac is Low.")
        #expect(FlickSetupAsk.line(speed: "High") == "A flick toward a nearby Mac is High.")
        #expect(cards(FlickSetupDraw.plan(speed: "High")) == ["Flick", "Speed: High"])
        #expect(cards(FlickSetupDraw.plan(speed: "Fast")) == ["Flick", "Can't"])
        #expect(FlickSetupAsk.line(speed: "Medium") == "I can't read the flick sensitivity.")
    }

    @Test func theRestOfFlingStaysOffThisAsk() {
        #expect(FlickSetupAsk.matches("how's flick set"))
        #expect(FlickSetupAsk.matches("Hey Zeus, which flick sensitivity?"))
        #expect(FlickSetupAsk.matches("flick settings"))
        #expect(!FlickSetupAsk.matches("how's fling set"))
        #expect(!FlickSetupAsk.matches("fling settings"))
        #expect(!FlickSetupAsk.matches("is the fast path on"))
        #expect(!FlickSetupAsk.matches("how's location set"))
    }
}
