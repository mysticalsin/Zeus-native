import Testing
@testable import ZeusCore

struct TodoSetupDrawTests {
    private func cards(_ plan: TodoSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallShowsTheTabAndLearnsWithoutMirroring() {
        let usual = TodoSetupDraw.plan(tab: "On", mirror: "Off", learn: "On")
        #expect(cards(usual) == ["Tasks", "Tab: On", "Mirror: Off", "Learn: On"])
        #expect(TodoSetupAsk.line(tab: "On", mirror: "Off", learn: "On") == "The to-do tab is on, Reminders mirror is off, and learning is on.")
        #expect(usual.boltCaption(at: 0) == "Tasks")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Learn: On")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(TodoSetupAsk.line(tab: "Off", mirror: "On", learn: "Off") == "The to-do tab is off, Reminders mirror is on, and learning is off.")
        #expect(cards(TodoSetupDraw.plan(tab: "Yes", mirror: "Off", learn: "On")) == ["Tasks", "Can't"])
        #expect(TodoSetupAsk.line(tab: "On", mirror: "Maybe", learn: "On") == "I can't read how to-dos are set.")
    }

    @Test func theOpenCountStaysOffThisAsk() {
        #expect(TodoSetupAsk.matches("how are to-dos set"))
        #expect(TodoSetupAsk.matches("Hey Zeus, is the to-do tab on?"))
        #expect(TodoSetupAsk.matches("does zeus learn from to-dos"))
        #expect(!TodoSetupAsk.matches("how many to-dos"))
        #expect(!TodoSetupAsk.matches("which tabs are on"))
        #expect(!TodoSetupAsk.matches("what is the second talk key"))
        #expect(!TodoSetupAsk.matches("what is the talk key"))
    }
}
