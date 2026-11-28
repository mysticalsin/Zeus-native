import Testing
@testable import ZeusCore

struct NotchCloseDrawTests {
    private func cards(_ plan: NotchCloseDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func hideAndWaitFollowClose() {
        let usual = NotchCloseDraw.plan(hide: "On", wait: "0.5 s")
        #expect(cards(usual) == ["Close", "Hide: On", "Wait: 0.5 s"])
        #expect(NotchCloseAsk.line(hide: "On", wait: "0.5 s") == "Auto-hide is on, and the close delay is 0.5 s.")
        #expect(usual.boltCaption(at: 0) == "Close")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Wait: 0.5 s")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(NotchCloseAsk.line(hide: "Off", wait: "Instantly") == "Auto-hide is off, and the close delay is Instantly.")
        #expect(cards(NotchCloseDraw.plan(hide: "On", wait: "2 s")) == ["Close", "Hide: On", "Wait: 2 s"])
        #expect(cards(NotchCloseDraw.plan(hide: "On", wait: "5 s")) == ["Close", "Can't"])
        #expect(NotchCloseAsk.line(hide: "Maybe", wait: "1 s") == "I can't read how the notch closes.")
    }

    @Test func whereItShowsAndHowItOpensStayOffThisAsk() {
        #expect(NotchCloseAsk.matches("how's the notch close"))
        #expect(NotchCloseAsk.matches("Hey Zeus, what's the close delay?"))
        #expect(NotchCloseAsk.matches("notch close settings"))
        #expect(!NotchCloseAsk.matches("how's the notch"))
        #expect(!NotchCloseAsk.matches("how does the notch open"))
        #expect(!NotchCloseAsk.matches("how's the screen corners"))
    }
}
