import Foundation
import Testing
@testable import ZeusCore

struct WeekDrawTests {
    private func cards(_ plan: WeekDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }

    @Test func aBusyWeekDrawsTheNumberThenTheCount() {
        let plan = WeekDraw.plan(week: 48, month: "November", count: 4)
        #expect(plan.map(cards) == ["Week", "48", "4 events"])
        #expect(WeekAsk.line(week: 48, month: "November", count: 4) == "Week 48 of November. You have 4 events.")
        #expect(WeekAsk.line(week: 48, month: "November", count: 1) == "Week 48 of November. You have 1 event.")
        #expect(WeekDraw.plan(week: 48, month: "November", count: 1).map(cards) == ["Week", "48", "1 event"])
        #expect(plan?.boltCaption(at: 0) == "Week")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "48")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "4 events")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(WeekDraw.plan(week: 0, month: "November", count: 1) == nil)
        #expect(WeekDraw.plan(week: 48, month: " ", count: 1) == nil)
    }

    @Test func aClearWeekCountsOnlyThatWeekAndTheAgendaIsNotThisAsk() {
        let calendar = calendar()
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
        let parts = WeekAsk.parts(now: now, calendar: calendar)
        #expect(parts?.month == "November")
        #expect(parts?.week == calendar.component(.weekOfYear, from: now))
        let inside = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))!
        let outside = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 9))!
        #expect(WeekAsk.count(starts: [inside, outside], now: now, calendar: calendar) == 1)
        let clear = WeekDraw.plan(week: 48, month: "November", count: 0)
        #expect(clear.map(cards) == ["Week", "48", "Clear"])
        #expect(WeekAsk.line(week: 48, month: "November", count: 0) == "Week 48 of November is clear.")
        #expect(cards(WeekDraw.access()) == ["Week", "Access"])
        #expect(WeekAsk.access == "I need Calendar access to read the week.")
        #expect(WeekAsk.matches("what's my week"))
        #expect(WeekAsk.matches("Hey Zeus, how busy is this week?"))
        #expect(WeekAsk.matches("this week"))
        #expect(!WeekAsk.matches("what's next"))
        #expect(!WeekAsk.matches("what's on my agenda"))
        #expect(!WeekAsk.matches("what's the date"))
        #expect(!WeekAsk.matches("how many meetings"))
        #expect(!WeekAsk.matches("will it rain"))
    }
}
