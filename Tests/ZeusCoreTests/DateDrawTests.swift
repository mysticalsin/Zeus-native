import Foundation
import Testing
@testable import ZeusCore

struct DateDrawTests {
    private func cards(_ plan: DateDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    private func at(timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 14, minute: 47))!
    }

    @Test func theDateDrawsTheWeekdayThenTheDay() {
        let plan = DateDraw.plan(weekday: "Wednesday", date: "4 November 2026")
        #expect(plan.map(cards) == ["Date", "Wednesday", "4 November 2026"])
        #expect(DateAsk.line(weekday: "Wednesday", date: "4 November 2026") == "It's Wednesday, 4 November 2026.")
        #expect(plan?.boltCaption(at: 0) == "Date")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "Wednesday")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "4 November 2026")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(DateDraw.plan(weekday: " ", date: "4 November 2026") == nil)
        #expect(DateDraw.plan(weekday: "Wednesday", date: " ") == nil)
        let zone = TimeZone(identifier: "America/Sao_Paulo")!
        let parts = DateAsk.parts(now: at(timeZone: zone), timeZone: zone)
        #expect(parts.weekday == "Wednesday")
        #expect(parts.date == "4 November 2026")
        #expect(DateAsk.line(weekday: parts.weekday, date: parts.date) == "It's Wednesday, 4 November 2026.")
    }

    @Test func aMeetingDayIsNotTodaysDate() {
        #expect(DateAsk.matches("what's the date"))
        #expect(DateAsk.matches("Hey Zeus, what day is it?"))
        #expect(DateAsk.matches("what's today's date"))
        #expect(DateAsk.matches("tell me the date"))
        #expect(!DateAsk.matches("what day is the meeting"))
        #expect(!DateAsk.matches("what time is it"))
        #expect(!DateAsk.matches("what's the countdown"))
        #expect(!DateAsk.matches("what time is it in Tokyo"))
        #expect(!DateAsk.matches("what's next"))
    }
}
