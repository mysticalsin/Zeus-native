import Testing
@testable import ZeusCore

struct RunningCardDrawTests {
    private func cards(_ plan: RunningCardDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func lookOpenAndWaitFollowRunning() {
        let usual = RunningCardDraw.plan(look: "Wave", open: "Hover", wait: "Normal")
        #expect(cards(usual) == ["Running", "Look: Wave", "Open: Hover", "Wait: Normal"])
        #expect(RunningCardAsk.line(look: "Wave", open: "Hover", wait: "Normal") == "The running card is Wave, it opens on Hover, and the hover delay is Normal.")
        #expect(usual.boltCaption(at: 0) == "Running")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Wait: Normal")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(RunningCardAsk.line(look: "Essentials", open: "Click", wait: "Fast") == "The running card is Essentials, it opens on Click, and the hover delay is Fast.")
        #expect(cards(RunningCardDraw.plan(look: "Wave", open: "Hover", wait: "Relaxed")) == ["Running", "Look: Wave", "Open: Hover", "Wait: Relaxed"])
        #expect(cards(RunningCardDraw.plan(look: "Bars", open: "Hover", wait: "Normal")) == ["Running", "Can't"])
        #expect(RunningCardAsk.line(look: "Wave", open: "Tap", wait: "Normal") == "I can't read the running card.")
    }

    @Test func openingTheNotchStaysOffThisAsk() {
        #expect(RunningCardAsk.matches("how's the running card set"))
        #expect(RunningCardAsk.matches("Hey Zeus, what's the hover delay?"))
        #expect(RunningCardAsk.matches("running card settings"))
        #expect(!RunningCardAsk.matches("how does the notch open"))
        #expect(!RunningCardAsk.matches("how's the notch open"))
        #expect(!RunningCardAsk.matches("which music lights"))
        #expect(!RunningCardAsk.matches("how's the halo arm"))
    }
}
