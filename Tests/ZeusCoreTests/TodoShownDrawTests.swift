import Testing
@testable import ZeusCore

struct TodoShownDrawTests {
    private func cards(_ plan: TodoShownDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func doneToDosAndVoiceAdd() {
        let usual = TodoShownDraw.plan(done: "Hidden", voice: "Off")
        #expect(cards(usual) == ["List", "Done: Hidden", "Voice: Off"])
        #expect(TodoShownAsk.line(done: "Hidden", voice: "Off") == "Done to-dos are hidden, and voice add is off.")
        #expect(usual.boltCaption(at: 0) == "List")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Voice: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(TodoShownAsk.line(done: "Shown", voice: "Off") == "Done to-dos are shown, and voice add is off.")
        #expect(TodoShownAsk.line(done: "Hidden", voice: "On") == "Done to-dos are hidden, and voice add is on.")
        #expect(cards(TodoShownDraw.plan(done: "Yes", voice: "Off")) == ["List", "Can't"])
        #expect(TodoShownAsk.line(done: "Hidden", voice: "Maybe") == "I can't read the to-do list.")
    }

    @Test func theOpenCountStaysOffThisAsk() {
        #expect(TodoShownAsk.matches("are done to-dos shown"))
        #expect(TodoShownAsk.matches("Hey Zeus, is voice add on?"))
        #expect(TodoShownAsk.matches("is the to-do mic on"))
        #expect(!TodoShownAsk.matches("how many to-dos"))
        #expect(!TodoShownAsk.matches("how are to-dos set"))
        #expect(!TodoShownAsk.matches("which tab is open"))
        #expect(!TodoShownAsk.matches("how many shelf files are verified"))
    }
}
