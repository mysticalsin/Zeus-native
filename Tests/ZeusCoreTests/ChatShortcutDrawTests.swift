import Testing
@testable import ZeusCore

struct ChatShortcutDrawTests {
    private func cards(_ plan: ChatShortcutDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theMenuTitleIsTheSecondCard() {
        let chord = ChatShortcutDraw.plan(word: "Control-Option-C")
        #expect(cards(chord) == ["Chat", "Control-Option-C"])
        #expect(ChatShortcutAsk.line(word: "Control-Option-C") == "Chat opens with Control, Option, and C.")
        #expect(chord.boltCaption(at: 0) == "Chat")
        #expect(chord.boltCaption(at: ExplainBeatSchedule.gap) == "Control-Option-C")
        #expect(chord.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(ChatShortcutAsk.line(word: "Off") == "The chat shortcut is off.")
        #expect(ChatShortcutAsk.line(word: "Option-Space") == "Chat opens with Option and Space.")
        #expect(ChatShortcutAsk.line(word: "Command-Shift-Space") == "Chat opens with Command, Shift, and Space.")
        #expect(cards(ChatShortcutDraw.plan(word: "Banana")) == ["Chat", "Can't"])
        #expect(ChatShortcutAsk.line(word: "") == "I can't read the chat shortcut.")
    }

    @Test func theChatCountAndThePointingKeysStayOffThisAsk() {
        #expect(ChatShortcutAsk.matches("what's the chat shortcut"))
        #expect(ChatShortcutAsk.matches("Hey Zeus, how do I open chat?"))
        #expect(ChatShortcutAsk.matches("how's the chat shortcut"))
        #expect(!ChatShortcutAsk.matches("how many chats"))
        #expect(!ChatShortcutAsk.matches("how's chat"))
        #expect(!ChatShortcutAsk.matches("what's the pointing key"))
        #expect(!ChatShortcutAsk.matches("where's the notch"))
    }
}
