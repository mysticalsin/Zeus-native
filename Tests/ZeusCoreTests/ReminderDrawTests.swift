import Foundation
import Testing
@testable import ZeusCore

struct ReminderDrawTests {
    private func cards(_ plan: ReminderDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aReminderDrawsTheTitleThenTheDueLine() {
        let plan = ReminderDraw.plan(title: "Pay rent", when: "Fri 5:00 PM")
        #expect(plan.map(cards) == ["Reminder", "Pay rent", "Fri 5:00 PM"])
        #expect(ReminderAsk.added(title: "Pay rent", when: "Fri 5:00 PM") == "Added Pay rent for Fri 5:00 PM.")
        #expect(ReminderAsk.added(title: "Pay rent", when: " ") == "Added Pay rent.")
        #expect(plan?.boltCaption(at: 0) == "Reminder")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "Pay rent")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Fri 5:00 PM")
        #expect(plan?.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        let bare = ReminderDraw.plan(title: "Call Ana", when: "")
        #expect(bare.map(cards) == ["Reminder", "Call Ana"])
        #expect(ReminderDraw.plan(title: "  ", when: "Friday") == nil)
        let zone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_763_000_000)
        #expect(!ReminderAsk.whenLine(date, hasTime: false, timeZone: zone).isEmpty)
        #expect(ReminderAsk.whenLine(date, hasTime: true, timeZone: zone).contains(":"))
    }

    @Test func accessAndAToDoAskStayOffThisCard() {
        #expect(cards(ReminderDraw.access()) == ["Reminder", "Access"])
        #expect(cards(ReminderDraw.notSaved()) == ["Reminder", "Not saved"])
        #expect(ReminderAsk.access == "I need Reminders access to add that.")
        #expect(ReminderAsk.notSaved == "The reminder wasn't saved.")
        #expect(ReminderAsk.body(in: "Hey Zeus, new reminder: pay rent friday at 5.") == "pay rent friday at 5")
        #expect(ReminderAsk.body(in: "add an apple reminder call Ana") == "call Ana")
        #expect(ReminderAsk.body(in: "remind me to call Ana") == nil)
        #expect(ReminderAsk.body(in: "what's my battery") == nil)
        #expect(ReminderAsk.body(in: "add pay rent to reminders") == nil)
    }
}
