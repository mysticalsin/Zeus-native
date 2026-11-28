import Testing
@testable import ZeusCore

struct ExtraKeyDrawTests {
    private func cards(_ plan: ExtraKeyDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallUsesRightOptionAndRightCommand() {
        let usual = ExtraKeyDraw.plan(second: "Default", dictate: "Default")
        #expect(cards(usual) == ["Extra", "Second: Default", "Dictate: Default"])
        #expect(ExtraKeyAsk.line(second: "Default", dictate: "Default") == "The second talk key is Right Option, and dictation uses the right Command key.")
        #expect(usual.boltCaption(at: 0) == "Extra")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Dictate: Default")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ExtraKeyAsk.line(second: "Off", dictate: "Off") == "The second talk key is off, and dictation has no shortcut.")
        #expect(ExtraKeyAsk.line(second: "Chosen", dictate: "Chosen") == "The second talk key is one you chose, and dictation uses a shortcut you chose.")
        #expect(cards(ExtraKeyDraw.plan(second: "Space", dictate: "Default")) == ["Extra", "Can't"])
        #expect(ExtraKeyAsk.line(second: "Default", dictate: "Maybe") == "I can't read the second talk key.")
    }

    @Test func theMainTalkKeyStaysOffThisAsk() {
        #expect(ExtraKeyAsk.matches("what is the second talk key"))
        #expect(ExtraKeyAsk.matches("Hey Zeus, what is the dictation shortcut?"))
        #expect(ExtraKeyAsk.matches("is the second talk key on"))
        #expect(!ExtraKeyAsk.matches("what is the talk key"))
        #expect(!ExtraKeyAsk.matches("what is the chat shortcut"))
        #expect(!ExtraKeyAsk.matches("how is dictation set"))
        #expect(!ExtraKeyAsk.matches("is the menu bar icon on"))
    }
}
