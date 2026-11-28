import Testing
@testable import ZeusCore

struct FlingNearbyDrawTests {
    private func cards(_ plan: FlingNearbyDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theStripAndTheMacs() {
        let usual = FlingNearbyDraw.plan(state: "Off", nearby: "0", ready: "0")
        #expect(cards(usual) == ["Nearby", "State: Off", "Nearby: 0", "Paired: 0"])
        #expect(FlingNearbyAsk.line(state: "Off", nearby: "0", ready: "0") == "Fling is off, and no nearby Macs are shown.")
        #expect(usual.boltCaption(at: 0) == "Nearby")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Paired: 0")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(FlingNearbyAsk.line(state: "Denied", nearby: "0", ready: "0") == "Local Network is off for Fling, and no nearby Macs are shown.")
        #expect(FlingNearbyAsk.line(state: "Looking", nearby: "0", ready: "0") == "Fling is looking, and no Macs are nearby.")
        #expect(FlingNearbyAsk.line(state: "Looking", nearby: "2", ready: "1") == "Fling is looking, 2 Macs are nearby, and 1 is paired.")
        #expect(cards(FlingNearbyDraw.plan(state: "Off", nearby: "1", ready: "0")) == ["Nearby", "Can't"])
        #expect(FlingNearbyAsk.line(state: "Looking", nearby: "1", ready: "2") == "I can't read the nearby Macs.")
    }

    @Test func savedPairsStayOffThisAsk() {
        #expect(FlingNearbyAsk.matches("how many macs are nearby"))
        #expect(FlingNearbyAsk.matches("Hey Zeus, is Fling looking?"))
        #expect(FlingNearbyAsk.matches("are any macs nearby"))
        #expect(!FlingNearbyAsk.matches("how many macs are paired"))
        #expect(!FlingNearbyAsk.matches("how is fling set"))
        #expect(!FlingNearbyAsk.matches("how many shelf files are verified"))
        #expect(!FlingNearbyAsk.matches("how is the prompter script set"))
    }
}
