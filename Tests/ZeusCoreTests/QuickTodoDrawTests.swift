import Testing
@testable import ZeusCore

struct QuickTodoDrawTests {
    private func cards(_ plan: QuickTodoDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theKeyAndThePicker() {
        let usual = QuickTodoDraw.plan(key: "⌃⌥ T", match: "Clear")
        #expect(cards(usual) == ["Quick", "Key: ⌃⌥ T", "Match: Clear"])
        #expect(QuickTodoAsk.line(key: "⌃⌥ T", match: "Clear") == "The quick to-do key is Control, Option, and T, and it does not match the agent picker.")
        #expect(usual.boltCaption(at: 0) == "Quick")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Match: Clear")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(QuickTodoAsk.line(key: "Off", match: "Clear") == "The quick to-do key is off, and it does not match the agent picker.")
        #expect(QuickTodoAsk.line(key: "⌥⌘ Z", match: "Same") == "The quick to-do key is Option, Command, and Z, and it is the same as the agent picker.")
        #expect(cards(QuickTodoDraw.plan(key: "Off", match: "Same")) == ["Quick", "Can't"])
        #expect(QuickTodoAsk.line(key: "Space", match: "Clear") == "I can't read the quick to-do key.")
    }

    @Test func theAgentPickerStaysOffThisAsk() {
        #expect(QuickTodoAsk.matches("what is the quick to-do key"))
        #expect(QuickTodoAsk.matches("Hey Zeus, does the quick to-do key clash?"))
        #expect(QuickTodoAsk.matches("is the quick to-do key off"))
        #expect(!QuickTodoAsk.matches("what is the agent picker shortcut"))
        #expect(!QuickTodoAsk.matches("how are to-dos set"))
        #expect(!QuickTodoAsk.matches("are done to-dos shown"))
        #expect(!QuickTodoAsk.matches("is focus running"))
    }
}
