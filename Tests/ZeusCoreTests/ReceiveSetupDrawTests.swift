import Testing
@testable import ZeusCore

struct ReceiveSetupDrawTests {
    private func cards(_ plan: ReceiveSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theSwitchesThatAreOnFollowReceive() {
        let usual = ReceiveSetupDraw.plan(words: ["Accept", "Closed", "Links", "Glow"])
        #expect(cards(usual) == ["Receive", "Accept", "Closed", "Links", "Glow"])
        #expect(ReceiveSetupAsk.line(words: ["Accept", "Closed", "Links", "Glow"]) == "Fling receiving has Accept, Closed, Links, and Glow on.")
        #expect(usual.boltCaption(at: 0) == "Receive")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Glow")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        let all = ReceiveSetupAsk.order
        #expect(cards(ReceiveSetupDraw.plan(words: all)) == ["Receive", "Accept", "Closed", "Links", "Papers"])
        #expect(ReceiveSetupAsk.line(words: all) == "Fling receiving has 5 on, starting Accept, Closed, Links, and Papers.")
        #expect(cards(ReceiveSetupDraw.plan(words: [])) == ["Receive", "None"])
        #expect(ReceiveSetupAsk.line(words: []) == "Fling receiving is off.")
        #expect(ReceiveSetupAsk.line(words: ["Accept"]) == "Fling receiving has Accept on.")
        #expect(cards(ReceiveSetupDraw.plan(words: ["Glow", "Accept"])) == ["Receive", "Can't"])
        #expect(ReceiveSetupAsk.line(words: ["Beep"]) == "I can't read Fling receiving.")
    }

    @Test func theShelfAndTheFlingSetupStayOffThisAsk() {
        #expect(ReceiveSetupAsk.matches("how's receiving set"))
        #expect(ReceiveSetupAsk.matches("Hey Zeus, which arrival switches?"))
        #expect(ReceiveSetupAsk.matches("receiving settings"))
        #expect(!ReceiveSetupAsk.matches("how's fling set"))
        #expect(!ReceiveSetupAsk.matches("what's on my shelf"))
        #expect(!ReceiveSetupAsk.matches("how's agent notices set"))
    }
}
