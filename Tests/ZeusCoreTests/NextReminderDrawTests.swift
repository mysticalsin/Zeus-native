import Testing
@testable import ZeusCore

struct NextReminderDrawTests {
    private func cards(_ plan: NextReminderDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theNextReminderDrawsTheTitleThenTheDueLine() {
        let plan = NextReminderDraw.plan(title: "Pay rent", when: "Fri 5:00 PM")
        #expect(plan.map(cards) == ["Due", "Pay rent", "Fri 5:00 PM"])
        #expect(NextReminderAsk.line(title: "Pay rent", when: "Fri 5:00 PM") == "Next reminder is Pay rent, Fri 5:00 PM.")
        #expect(NextReminderAsk.line(title: "Pay rent", when: "") == "Next reminder is Pay rent.")
        #expect(plan?.boltCaption(at: 0) == "Due")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "Pay rent")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Fri 5:00 PM")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(NextReminderDraw.plan(title: " ", when: "Friday") == nil)
        let open = NextReminderDraw.plan(title: "Call Ana", when: " ")
        #expect(open.map(cards) == ["Due", "Call Ana"])
    }

    @Test func nothingLeftDrawsNoneAndAddingIsNotThisAsk() {
        #expect(cards(NextReminderDraw.none()) == ["Due", "None"])
        #expect(cards(NextReminderDraw.access()) == ["Due", "Access"])
        #expect(NextReminderAsk.none == "There's no reminder left.")
        #expect(NextReminderAsk.access == "I need Reminders access.")
        #expect(NextReminderAsk.matches("what's my next reminder"))
        #expect(NextReminderAsk.matches("Hey Zeus, next reminder"))
        #expect(!NextReminderAsk.matches("new reminder: pay rent"))
        #expect(!NextReminderAsk.matches("what's next"))
        #expect(!NextReminderAsk.matches("remind me to pay rent"))
        #expect(!NextReminderAsk.matches("how much time is left"))
    }
}
