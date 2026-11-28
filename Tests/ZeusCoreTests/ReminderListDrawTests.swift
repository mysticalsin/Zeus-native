import Testing
@testable import ZeusCore

struct ReminderListDrawTests {
    private func cards(_ plan: ReminderListDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theOpenListAndWaitingDue() {
        let usual = ReminderListDraw.plan(list: "All", due: "None")
        #expect(cards(usual) == ["Lists", "List: All", "Due: None"])
        #expect(ReminderListAsk.line(list: "All", due: "None") == "Reminders are showing All, and no due time is waiting.")
        #expect(usual.boltCaption(at: 0) == "Lists")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Due: None")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ReminderListAsk.line(list: "Today", due: "In 1 hour") == "Reminders are showing Today, and the next one is due in an hour.")
        #expect(ReminderListAsk.line(list: "Flagged", due: "Next week") == "Reminders are showing Flagged, and the next one is due next week.")
        #expect(ReminderListAsk.line(list: "Scheduled", due: "This evening") == "Reminders are showing Scheduled, and the next one is due this evening.")
        #expect(ReminderListAsk.line(list: "All", due: "Tomorrow 9:00") == "Reminders are showing All, and the next one is due tomorrow at 9.")
        #expect(cards(ReminderListDraw.plan(list: "Later", due: "None")) == ["Lists", "Can't"])
        #expect(ReminderListAsk.line(list: "All", due: "Soon") == "I can't read the reminder list.")
    }

    @Test func theNextReminderStaysOffThisAsk() {
        #expect(ReminderListAsk.matches("which reminders are showing"))
        #expect(ReminderListAsk.matches("Hey Zeus, which reminder filter?"))
        #expect(ReminderListAsk.matches("is a due time waiting"))
        #expect(!ReminderListAsk.matches("what is my next reminder"))
        #expect(!ReminderListAsk.matches("how many to-dos"))
        #expect(!ReminderListAsk.matches("is shuffle on"))
        #expect(!ReminderListAsk.matches("how long is a focus round"))
    }
}
