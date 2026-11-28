import Testing
@testable import ZeusCore

struct PickerSetupDrawTests {
    private func cards(_ plan: PickerSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func answerAndOpenFollowPicker() {
        let usual = PickerSetupDraw.plan(answer: "On", open: "⌥⌘ Z")
        #expect(cards(usual) == ["Picker", "Answer: On", "Open: ⌥⌘ Z"])
        #expect(PickerSetupAsk.line(answer: "On", open: "⌥⌘ Z") == "Keyboard answers are on, and the agent picker opens with Option, Command, and Z.")
        #expect(usual.boltCaption(at: 0) == "Picker")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Open: ⌥⌘ Z")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(PickerSetupAsk.line(answer: "Off", open: "Off") == "Keyboard answers are off, and the agent picker shortcut is off.")
        #expect(PickerSetupAsk.line(answer: "On", open: "⌃⌥ Space") == "Keyboard answers are on, and the agent picker opens with Control, Option, and Space.")
        #expect(cards(PickerSetupDraw.plan(answer: "Off", open: "⌥⌘ T")) == ["Picker", "Answer: Off", "Open: ⌥⌘ T"])
        #expect(cards(PickerSetupDraw.plan(answer: "On", open: "Command-Z")) == ["Picker", "Can't"])
        #expect(PickerSetupAsk.line(answer: "Maybe", open: "Off") == "I can't read the agent picker shortcut.")
    }

    @Test func theChatShortcutStaysOffThisAsk() {
        #expect(PickerSetupAsk.matches("what's the agent picker shortcut"))
        #expect(PickerSetupAsk.matches("Hey Zeus, are answer keys on?"))
        #expect(PickerSetupAsk.matches("agent picker settings"))
        #expect(!PickerSetupAsk.matches("what's the chat shortcut"))
        #expect(!PickerSetupAsk.matches("which chat shortcut"))
        #expect(!PickerSetupAsk.matches("how's jev set"))
        #expect(!PickerSetupAsk.matches("which other permissions"))
    }
}
