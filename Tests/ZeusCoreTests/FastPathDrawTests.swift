import Testing
@testable import ZeusCore

struct FastPathDrawTests {
    private func cards(_ plan: FastPathDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theSwitchFollowsFast() {
        let usual = FastPathDraw.plan(work: "On")
        #expect(cards(usual) == ["Fast", "Work: On"])
        #expect(FastPathAsk.line(work: "On") == "Simple commands run as you finish speaking.")
        #expect(usual.boltCaption(at: 0) == "Fast")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap + 0.001) == "Work: On")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap + 0.001) == TalkDraw.Point(x: 920, y: 180))
        #expect(FastPathAsk.line(work: "Off") == "Simple commands go to the AI.")
        #expect(cards(FastPathDraw.plan(work: "Off")) == ["Fast", "Work: Off"])
        #expect(cards(FastPathDraw.plan(work: "Maybe")) == ["Fast", "Can't"])
        #expect(FastPathAsk.line(work: "Slow") == "I can't read the fast path.")
    }

    @Test func jevStaysOffThisAsk() {
        #expect(FastPathAsk.matches("is the fast path on"))
        #expect(FastPathAsk.matches("Hey Zeus, do simple commands run at once?"))
        #expect(FastPathAsk.matches("fast path settings"))
        #expect(!FastPathAsk.matches("how's jev set"))
        #expect(!FastPathAsk.matches("is jev on"))
        #expect(!FastPathAsk.matches("which default agent"))
        #expect(!FastPathAsk.matches("how's location set"))
    }
}
