import Testing
@testable import ZeusCore

struct HookShowDrawTests {
    private func cards(_ plan: HookShowDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshMacShowsNoneOfTheOtherAgents() {
        let usual = HookShowDraw.plan(codex: "Off", gemini: "Off", cursor: "Off")
        #expect(cards(usual) == ["Hooks", "Codex: Off", "Gemini: Off", "Cursor: Off"])
        #expect(HookShowAsk.line(codex: "Off", gemini: "Off", cursor: "Off") == "Codex does not show in the notch, Gemini CLI does not show in the notch, and Cursor Agent does not show in the notch.")
        #expect(usual.boltCaption(at: 0) == "Hooks")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Cursor: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(HookShowAsk.line(codex: "On", gemini: "Off", cursor: "On") == "Codex shows in the notch, Gemini CLI does not show in the notch, and Cursor Agent shows in the notch.")
        #expect(cards(HookShowDraw.plan(codex: "Yes", gemini: "Off", cursor: "Off")) == ["Hooks", "Can't"])
        #expect(HookShowAsk.line(codex: "On", gemini: "Maybe", cursor: "Off") == "I can't read which other agents show in the notch.")
    }

    @Test func aNewChatOfferStaysOffThisAsk() {
        #expect(HookShowAsk.matches("which other agents show in the notch"))
        #expect(HookShowAsk.matches("Hey Zeus, is Cursor Agent in the notch?"))
        #expect(HookShowAsk.matches("how are the other agents hooked"))
        #expect(!HookShowAsk.matches("are cursor and gemini offered"))
        #expect(!HookShowAsk.matches("which agents are offered"))
        #expect(!HookShowAsk.matches("how is coding set"))
        #expect(!HookShowAsk.matches("how are finished agents shown"))
    }
}
