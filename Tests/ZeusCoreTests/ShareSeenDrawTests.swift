import Testing
@testable import ZeusCore

struct ShareSeenDrawTests {
    private func cards(_ plan: ShareSeenDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshShareHidesZeus() {
        let usual = ShareSeenDraw.plan(share: "Off", hide: "Off", seen: "Hidden")
        #expect(cards(usual) == ["Seen", "Share: Off", "Hide: Off", "Shares: Hidden"])
        #expect(ShareSeenAsk.line(share: "Off", hide: "Off", seen: "Hidden") == "The share switch is off, the hide switch is off, and screen shares do not show Zeus.")
        #expect(usual.boltCaption(at: 0) == "Seen")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Shares: Hidden")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(ShareSeenAsk.line(share: "On", hide: "Off", seen: "Hidden") == "The share switch is on, the hide switch is off, and screen shares do not show Zeus.")
        #expect(ShareSeenAsk.line(share: "Off", hide: "On", seen: "Shown") == "The share switch is off, the hide switch is on, and screen shares show Zeus.")
        #expect(cards(ShareSeenDraw.plan(share: "Yes", hide: "Off", seen: "Hidden")) == ["Seen", "Can't"])
        #expect(ShareSeenAsk.line(share: "Off", hide: "Off", seen: "Maybe") == "I can't read whether screen sharing hides Zeus.")
    }

    @Test func dayToDayStaysOffThisAsk() {
        #expect(ShareSeenAsk.matches("do screen shares show zeus"))
        #expect(ShareSeenAsk.matches("Hey Zeus, is Zeus hidden from screen sharing?"))
        #expect(ShareSeenAsk.matches("is the hide from sharing switch on"))
        #expect(!ShareSeenAsk.matches("what is on day to day"))
        #expect(!ShareSeenAsk.matches("how is the prompter set"))
        #expect(!ShareSeenAsk.matches("do permission requests always show"))
        #expect(!ShareSeenAsk.matches("how do question answers go back"))
    }
}
