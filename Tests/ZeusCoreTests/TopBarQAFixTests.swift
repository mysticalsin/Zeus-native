import Foundation
import Testing
@testable import ZeusCore

@Suite("Top bar QA fixes")
struct TopBarQAFixTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private static let now = Date(timeIntervalSince1970: 1_793_000_000)

    @Test("absurd durations are ignored instead of overflowing")
    func hugeDurationDoesNotTrap() {
        for text in ["lunch for 999999999999999999 hours", "lunch for 9223372036854775807 hours",
                     "lunch tomorrow at 1 pm for 99999999999999999 minutes", "lunch for 92233720368547758 hours"] {
            let parsed = CalendarQuickAdd.parse(text, now: Self.now, calendar: Self.calendar)
            #expect(parsed != nil)
        }
    }

    @Test("a sensible duration still sets the end")
    func normalDuration() throws {
        let parsed = try #require(CalendarQuickAdd.parse("lunch tomorrow at 1 pm for 2 hours", now: Self.now, calendar: Self.calendar))
        #expect(parsed.end.timeIntervalSince(parsed.start) == 2 * 3600)
        let short = try #require(CalendarQuickAdd.parse("call tomorrow at 1 pm for 30 minutes", now: Self.now, calendar: Self.calendar))
        #expect(short.end.timeIntervalSince(short.start) == 30 * 60)
    }
}
