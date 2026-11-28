import Testing
@testable import ZeusCore

struct EarbudsStatusDrawTests {
    private func cards(_ plan: EarbudsStatusDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func connectedDrawsTheNotchWordThenTheName() {
        let plan = EarbudsStatusDraw.plan(connected: true, name: "AirPods Pro")
        #expect(cards(plan) == ["Earbuds", "Connected", "AirPods Pro"])
        #expect(EarbudsStatusAsk.line(connected: true, name: "AirPods Pro") == "AirPods Pro connected.")
        #expect(plan.boltCaption(at: 0) == "Earbuds")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "Connected")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap * 2) == "AirPods Pro")
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        let unread = EarbudsStatusDraw.plan(connected: nil, name: "AirPods Pro")
        #expect(cards(unread) == ["Earbuds", "Can't"])
        #expect(EarbudsStatusAsk.line(connected: nil, name: "AirPods Pro") == "I can't see the sound output.")
        #expect(EarbudsStatusAsk.cardName("Air\nPods") == "Air Pods")
    }

    @Test func disconnectedLeavesTheDeviceNameOff() {
        let off = EarbudsStatusDraw.plan(connected: false, name: "MacBook Speakers")
        #expect(cards(off) == ["Earbuds", "Disconnected"])
        #expect(EarbudsStatusAsk.line(connected: false, name: "MacBook Speakers") == "Earbuds disconnected.")
        #expect(off.boltCaption(at: ExplainBeatSchedule.gap) == "Disconnected")
        #expect(off.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        let plain = EarbudsStatusDraw.plan(connected: true, name: "  Earbuds  ")
        #expect(cards(plain) == ["Earbuds", "Connected"])
        #expect(EarbudsStatusAsk.line(connected: true, name: " ") == "Earbuds connected.")
        #expect(EarbudsStatusAsk.matches("are my earbuds connected"))
        #expect(EarbudsStatusAsk.matches("Hey Zeus, how's my airpods?"))
        #expect(EarbudsStatusAsk.matches("airpods"))
        #expect(!EarbudsStatusAsk.matches("what's playing"))
        #expect(!EarbudsStatusAsk.matches("how many screens"))
        #expect(!EarbudsStatusAsk.matches("is tiling on"))
        #expect(!EarbudsStatusAsk.matches("play Kind of Blue on Spotify"))
        #expect(!EarbudsStatusAsk.matches("are you recording"))
    }
}
