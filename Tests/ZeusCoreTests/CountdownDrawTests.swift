import Foundation
import Testing
@testable import ZeusCore

struct CountdownDrawTests {
    private func cards(_ plan: CountdownDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    private var zone: TimeZone { TimeZone(identifier: "America/Sao_Paulo")! }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private func at(day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 14, minute: 47))!
    }

    @Test func aCountdownDrawsTheTitleThenTheCount() {
        let plan = CountdownDraw.plan(title: "Launch day", days: 12)
        #expect(cards(plan) == ["Countdown", "Launch day", "12 days"])
        #expect(CountdownAsk.line(title: "Launch day", days: 12) == "Launch day is in 12 days.")
        #expect(CountdownAsk.line(title: "Launch day", days: 1) == "Launch day is in 1 day.")
        #expect(CountdownAsk.line(title: "Launch day", days: 0) == "Launch day is today.")
        #expect(CountdownAsk.line(title: "Launch day", days: -1) == "Launch day was 1 day ago.")
        #expect(CountdownAsk.line(title: "Launch day", days: -3) == "Launch day was 3 days ago.")
        #expect(CountdownAsk.line(title: " ", days: 12) == "The countdown is in 12 days.")
        #expect(plan.boltCaption(at: 0) == "Countdown")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "Launch day")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap * 2) == "12 days")
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        let bare = CountdownDraw.plan(title: " ", days: 0)
        #expect(cards(bare) == ["Countdown", "Today"])
        let now = at(day: 4)
        #expect(CountdownAsk.days(to: at(day: 28), now: now, calendar: calendar) == 24)
        #expect(CountdownAsk.days(to: at(day: 5), now: now, calendar: calendar) == 1)
        #expect(CountdownAsk.days(to: now, now: now, calendar: calendar) == 0)
        #expect(CountdownAsk.days(to: at(day: 3), now: now, calendar: calendar) == -1)
    }

    @Test func noDateDrawsNoneAndATimerIsNotThisAsk() {
        #expect(cards(CountdownDraw.none()) == ["Countdown", "None"])
        #expect(CountdownAsk.none == "Pick a countdown in Settings.")
        #expect(CountdownAsk.matches("what's the countdown"))
        #expect(CountdownAsk.matches("Hey Zeus, how many days left?"))
        #expect(CountdownAsk.matches("days left"))
        #expect(!CountdownAsk.matches("how many days until Friday"))
        #expect(!CountdownAsk.matches("set a timer for 5 minutes"))
        #expect(!CountdownAsk.matches("what time is it"))
        #expect(!CountdownAsk.matches("what's next"))
        #expect(!CountdownAsk.matches("what time is it in Tokyo"))
    }
}
