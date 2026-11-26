import Foundation
import Testing
@testable import ZeusCore

@Suite("Reminder filters box")
struct ReminderFiltersBoxTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// Wednesday 4 November 2026, 14:07 UTC.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 14, minute: 7, second: 0))!
    }

    private func parts(_ date: Date) -> (day: Int, hour: Int, minute: Int, weekday: Int) {
        let components = calendar.dateComponents([.day, .hour, .minute, .weekday], from: date)
        return (components.day!, components.hour!, components.minute!, components.weekday!)
    }

    private func at(day: Int, hour: Int, minute: Int, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
    }

    private func keptTitle(_ remaining: String) -> (title: String, due: Date?) {
        (title: remaining, due: nil)
    }

    @Test func todayKeepsOverdueAndLaterToday() {
        let yesterday = now.addingTimeInterval(-86400)
        let later = now.addingTimeInterval(3600)
        #expect(ReminderFiltersBox.includes(.today, due: yesterday, flagged: false, now: now, calendar: calendar))
        #expect(ReminderFiltersBox.includes(.today, due: later, flagged: false, now: now, calendar: calendar))
        #expect(ReminderFiltersBox.includes(.today, due: at(day: 4, hour: 0, minute: 0), flagged: false, now: now, calendar: calendar))
        #expect(ReminderFiltersBox.includes(.today, due: at(day: 4, hour: 23, minute: 59, second: 59), flagged: false, now: now, calendar: calendar))
    }

    @Test func todayDropsTomorrowAndAMissingDue() {
        let startOfTomorrow = at(day: 5, hour: 0, minute: 0)
        #expect(ReminderFiltersBox.includes(.today, due: yesterdaySafe(), flagged: false, now: now, calendar: calendar))
        #expect(!ReminderFiltersBox.includes(.today, due: startOfTomorrow, flagged: true, now: now, calendar: calendar))
        #expect(!ReminderFiltersBox.includes(.today, due: at(day: 11, hour: 9, minute: 0), flagged: false, now: now, calendar: calendar))
        #expect(!ReminderFiltersBox.includes(.today, due: nil, flagged: true, now: now, calendar: calendar))
    }

    @Test func scheduledIsAnyDueDateAndAllKeepsEverything() {
        #expect(ReminderFiltersBox.includes(.scheduled, due: at(day: 11, hour: 9, minute: 0), flagged: false, now: now, calendar: calendar))
        #expect(ReminderFiltersBox.includes(.scheduled, due: now, flagged: false, now: now, calendar: calendar))
        #expect(!ReminderFiltersBox.includes(.scheduled, due: nil, flagged: true, now: now, calendar: calendar))
        #expect(ReminderFiltersBox.includes(.all, due: nil, flagged: false, now: now, calendar: calendar))
        #expect(ReminderFiltersBox.includes(.all, due: now, flagged: true, now: now, calendar: calendar))
    }

    @Test func flaggedReadsTheMarkAndIgnoresTheDueDate() {
        #expect(ReminderFiltersBox.includes(.flagged, due: nil, flagged: true, now: now, calendar: calendar))
        #expect(ReminderFiltersBox.includes(.flagged, due: at(day: 20, hour: 1, minute: 0), flagged: true, now: now, calendar: calendar))
        #expect(!ReminderFiltersBox.includes(.flagged, due: now, flagged: false, now: now, calendar: calendar))
        #expect(!ReminderFiltersBox.includes(.flagged, due: nil, flagged: false, now: now, calendar: calendar))
    }

    @Test func thisEveningIsEighteenHundredUntilThatHour() {
        let evening = ReminderFiltersBox.quickDue(.thisEvening, now: now, calendar: calendar)
        #expect(parts(evening) == (4, 18, 0, 4))
        let justBefore = ReminderFiltersBox.quickDue(.thisEvening, now: at(day: 4, hour: 17, minute: 59), calendar: calendar)
        #expect(parts(justBefore) == (4, 18, 0, 4))
    }

    @Test func thisEveningRollsToTomorrowAtEighteenHundred() {
        let onTheHour = ReminderFiltersBox.quickDue(.thisEvening, now: at(day: 4, hour: 18, minute: 0), calendar: calendar)
        let after = ReminderFiltersBox.quickDue(.thisEvening, now: at(day: 4, hour: 19, minute: 30), calendar: calendar)
        #expect(parts(onTheHour) == (5, 18, 0, 5))
        #expect(parts(after) == (5, 18, 0, 5))
    }

    @Test func tomorrowMorningIsNineTheNextDay() {
        let morning = ReminderFiltersBox.quickDue(.tomorrowMorning, now: now, calendar: calendar)
        #expect(parts(morning) == (5, 9, 0, 5))
        let late = ReminderFiltersBox.quickDue(.tomorrowMorning, now: at(day: 4, hour: 23, minute: 59), calendar: calendar)
        #expect(parts(late) == (5, 9, 0, 5))
    }

    @Test func nextWeekIsTheComingMondayAtNine() {
        let wednesday = ReminderFiltersBox.quickDue(.nextWeek, now: now, calendar: calendar)
        #expect(parts(wednesday) == (9, 9, 0, 2))
        let sunday = ReminderFiltersBox.quickDue(.nextWeek, now: at(day: 1, hour: 12, minute: 0), calendar: calendar)
        #expect(parts(sunday) == (2, 9, 0, 2))
        let monday = ReminderFiltersBox.quickDue(.nextWeek, now: at(day: 2, hour: 9, minute: 0), calendar: calendar)
        #expect(parts(monday) == (9, 9, 0, 2))
        let saturday = ReminderFiltersBox.quickDue(.nextWeek, now: at(day: 7, hour: 8, minute: 0), calendar: calendar)
        #expect(parts(saturday) == (9, 9, 0, 2))
    }

    @Test func inAnHourLandsOnTheNextQuarterHour() {
        let fromNow = ReminderFiltersBox.quickDue(.inAnHour, now: now, calendar: calendar)
        #expect(parts(fromNow) == (4, 15, 15, 4))
        let exact = ReminderFiltersBox.quickDue(.inAnHour, now: at(day: 4, hour: 14, minute: 0), calendar: calendar)
        #expect(parts(exact) == (4, 15, 0, 4))
        let onePast = ReminderFiltersBox.quickDue(.inAnHour, now: at(day: 4, hour: 14, minute: 1), calendar: calendar)
        #expect(parts(onePast) == (4, 15, 15, 4))
        let towardTheHour = ReminderFiltersBox.quickDue(.inAnHour, now: at(day: 4, hour: 14, minute: 46), calendar: calendar)
        #expect(parts(towardTheHour) == (4, 16, 0, 4))
    }

    @Test func aFridayAtFiveKeepsTheTitleAndTheHour() {
        let draft = ReminderDraft.parse("pay rent friday at 5pm", now: now, calendar: calendar)
        #expect(draft.title == "pay rent")
        #expect(draft.hasTime)
        #expect(calendar.component(.hour, from: due(draft.due)) == 17)
        #expect(calendar.component(.minute, from: due(draft.due)) == 0)
        #expect(calendar.component(.weekday, from: due(draft.due)) == 6)
        #expect(calendar.component(.day, from: due(draft.due)) == 6)
    }

    @Test func aPastClockWithNoDayMovesToTomorrow() {
        let draft = ReminderDraft.parse("call Ana at 9:30", now: now, calendar: calendar)
        #expect(draft.title == "call Ana")
        #expect(draft.hasTime)
        #expect(parts(due(draft.due)) == (5, 9, 30, 5))
        let stillAhead = ReminderDraft.parse("standup at 9:30", now: at(day: 4, hour: 8, minute: 0), calendar: calendar)
        #expect(stillAhead.title == "standup")
        #expect(parts(due(stillAhead.due)) == (4, 9, 30, 4))
        let exact = ReminderDraft.parse("standup at 9:30", now: at(day: 4, hour: 9, minute: 30), calendar: calendar)
        #expect(parts(due(exact.due)) == (5, 9, 30, 5))
    }

    @Test func aBareNumberAndADayWithoutAClockStayUntimed() {
        let number = ReminderDraft.parse("buy 2", now: now, calendar: calendar)
        #expect(number.title == "buy 2")
        #expect(number.due == nil)
        #expect(!number.hasTime)
        let tomorrow = ReminderDraft.parse("water plants tomorrow", now: now, calendar: calendar)
        #expect(tomorrow.title == "water plants")
        #expect(!tomorrow.hasTime)
        #expect(calendar.component(.day, from: due(tomorrow.due)) == 5)
        let spaced = ReminderDraft.parse("pay rent at 5 pm", now: now, calendar: calendar)
        #expect(spaced.title == "pay rent")
        #expect(spaced.hasTime)
        #expect(parts(due(spaced.due)) == (4, 17, 0, 4))
    }

    @Test func theClockAcceptsAnAtHourAndRejectsABrokenClock() {
        let bare = ReminderFiltersBox.draft("at 9", now: at(day: 4, hour: 8, minute: 0), calendar: calendar, day: keptTitle)
        #expect(bare.title == "")
        #expect(bare.hasTime)
        #expect(parts(due(bare.due)) == (4, 9, 0, 4))
        let twentyFour = ReminderFiltersBox.draft("at 17:30", now: now, calendar: calendar, day: keptTitle)
        #expect(twentyFour.title == "")
        #expect(parts(due(twentyFour.due)) == (4, 17, 30, 4))
        let broken = ReminderFiltersBox.draft("meet at 13pm", now: now, calendar: calendar, day: keptTitle)
        #expect(broken.title == "meet at 13pm")
        #expect(broken.due == nil)
        #expect(!broken.hasTime)
        let minute = ReminderFiltersBox.draft("meet at 5:60", now: now, calendar: calendar, day: keptTitle)
        #expect(minute.title == "meet at 5:60")
        #expect(!minute.hasTime)
    }

    @Test func thePublicTypesReadTheBox() {
        let samples: [(ReminderFilter, Date?, Bool)] = [
            (.today, now, false),
            (.today, nil, true),
            (.scheduled, at(day: 11, hour: 9, minute: 0), false),
            (.scheduled, nil, true),
            (.all, nil, false),
            (.flagged, nil, true),
            (.flagged, now, false),
        ]
        for (filter, due, flagged) in samples {
            #expect(filter.includes(due: due, flagged: flagged, now: now, calendar: calendar)
                == ReminderFiltersBox.includes(filter, due: due, flagged: flagged, now: now, calendar: calendar))
        }
        #expect(ReminderFilter.all.includes(due: nil, flagged: false, now: now, calendar: calendar))
        #expect(ReminderFilter.today.includes(due: now, flagged: false, now: now, calendar: calendar))
        for kind in ReminderQuickDue.allCases {
            let fromType = kind.date(now: now, calendar: calendar)
            let fromBox = ReminderFiltersBox.quickDue(kind, now: now, calendar: calendar)
            #expect(fromType == fromBox)
            #expect(fromType != Date(timeIntervalSince1970: 0))
        }
        let parsed = ReminderDraft.parse("pay rent friday at 5pm", now: now, calendar: calendar)
        #expect(parsed.title == "pay rent")
        #expect(parsed.hasTime)
        #expect(calendar.component(.hour, from: due(parsed.due)) == 17)
    }

    private func yesterdaySafe() -> Date { now.addingTimeInterval(-86400) }

    /// A missing due still fails the expectation, and the later part checks see a date that cannot match.
    private func due(_ date: Date?) -> Date {
        #expect(date != nil)
        return date ?? Date(timeIntervalSince1970: 1)
    }
}
