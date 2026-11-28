import Testing
@testable import ZeusCore

struct LiveTouchDrawTests {
    private func cards(_ plan: LiveTouchDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallShowsCuesAndSitsByTheCursor() {
        let usual = LiveTouchDraw.plan(cues: "On", cursor: "On")
        #expect(cards(usual) == ["Touch", "Cues: On", "Cursor: On"])
        #expect(LiveTouchAsk.line(cues: "On", cursor: "On") == "Quick cues are on, and Zeus sits next to the cursor.")
        #expect(usual.boltCaption(at: 0) == "Touch")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Cursor: On")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(LiveTouchAsk.line(cues: "Off", cursor: "Off") == "Quick cues are off, and Zeus stays off the cursor.")
        #expect(LiveTouchAsk.line(cues: "On", cursor: "Off") == "Quick cues are on, and Zeus stays off the cursor.")
        #expect(cards(LiveTouchDraw.plan(cues: "Yes", cursor: "On")) == ["Touch", "Can't"])
        #expect(LiveTouchAsk.line(cues: "On", cursor: "Maybe") == "I can't read the live touches.")
    }

    @Test func theBuddyShowRuleStaysOffThisAsk() {
        #expect(LiveTouchAsk.matches("are quick cues on"))
        #expect(LiveTouchAsk.matches("Hey Zeus, does Zeus sit next to the cursor?"))
        #expect(LiveTouchAsk.matches("is the cursor presence on"))
        #expect(!LiveTouchAsk.matches("when does zeus appear"))
        #expect(!LiveTouchAsk.matches("which music lights"))
        #expect(!LiveTouchAsk.matches("does a session keep the display awake"))
        #expect(!LiveTouchAsk.matches("what is the polyglot key"))
    }
}
