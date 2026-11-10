import Foundation
import Testing
@testable import ZeusCore

@Suite("W6 integration follow-ups")
struct W6IntegTests {
    // `tick` counts days in the local Gregorian calendar, so the tests build their dates in it too.
    private static var calendar: Calendar { Calendar(identifier: .gregorian) }

    private static func date(_ day: Int, hour: Int = 10) -> Date {
        Self.calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test func roundsCountOnTheDayTheyFinished() {
        var timer = FocusTimer(focusLength: 60, restLength: 30)
        timer.start(.focus, at: Self.date(8))
        _ = timer.tick(at: Self.date(8).addingTimeInterval(61))
        #expect(timer.completedRounds == 1)
        #expect(timer.roundsToday(at: Self.date(8), calendar: Self.calendar) == 1)
    }

    @Test func roundsResetWhenTheDateChanges() {
        var timer = FocusTimer(focusLength: 60, restLength: 30)
        timer.start(.focus, at: Self.date(8))
        _ = timer.tick(at: Self.date(8).addingTimeInterval(61))
        #expect(timer.roundsToday(at: Self.date(9), calendar: Self.calendar) == 0)
    }

    @Test func roundsWithoutADayDoNotCountAsToday() throws {
        let saved = #"{"focusLength":1500,"restLength":300,"phase":"idle","completedRounds":4}"#
        let timer = try JSONDecoder().decode(FocusTimer.self, from: Data(saved.utf8))
        #expect(timer.roundsToday(at: Self.date(8), calendar: Self.calendar) == 0)
    }

    @Test func dayKeyIsZeroPadded() {
        #expect(FocusTimer.dayKey(Self.date(8), calendar: Self.calendar) == "2026-11-08")
    }
}
