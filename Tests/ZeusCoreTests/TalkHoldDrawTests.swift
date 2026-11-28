import Testing
@testable import ZeusCore

struct TalkHoldDrawTests {
    private func cards(_ plan: TalkHoldDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallHoldsControlOptionWithCaptions() {
        let usual = TalkHoldDraw.plan(key: "Default", captions: "On")
        #expect(cards(usual) == ["Hold", "Key: Default", "Words: On"])
        #expect(TalkHoldAsk.line(key: "Default", captions: "On") == "The talk key is Control and Option, and captions are on.")
        #expect(usual.boltCaption(at: 0) == "Hold")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Words: On")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(TalkHoldAsk.line(key: "Chosen", captions: "Off") == "The talk key is one you chose, and captions are off.")
        #expect(cards(TalkHoldDraw.plan(key: "Space", captions: "On")) == ["Hold", "Can't"])
        #expect(TalkHoldAsk.line(key: "Default", captions: "Maybe") == "I can't read the talk key.")
    }

    @Test func theChatShortcutStaysOffThisAsk() {
        #expect(TalkHoldAsk.matches("what is the talk key"))
        #expect(TalkHoldAsk.matches("Hey Zeus, are bolt captions on?"))
        #expect(TalkHoldAsk.matches("how is the talk key set"))
        #expect(!TalkHoldAsk.matches("what is the chat shortcut"))
        #expect(!TalkHoldAsk.matches("which talk microphone"))
        #expect(!TalkHoldAsk.matches("is the menu bar icon on"))
        #expect(!TalkHoldAsk.matches("is show me on"))
    }
}
