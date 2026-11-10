import Foundation

/// The month grid on the Calendar page and the Home month widgets: whole weeks, in the Mac's first weekday.
public enum CalendarGrid {
    /// The weeks that cover `month` (4 to 6 rows of 7 days, each at the start of its day).
    public static func weeks(month: Date, calendar: Calendar) -> [[Date]] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let first = calendar.dateInterval(of: .weekOfMonth, for: interval.start)?.start else { return [] }
        let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        var weeks: [[Date]] = []
        var cursor = first
        while cursor <= lastDay {
            weeks.append((0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: cursor) })
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    /// From the first shown day to the end of the last shown day (what to ask the calendar for).
    public static func visibleRange(month: Date, calendar: Calendar) -> Range<Date> {
        let weeks = weeks(month: month, calendar: calendar)
        guard let first = weeks.first?.first, let last = weeks.last?.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return month..<month.addingTimeInterval(1) }
        return first..<end
    }

    /// Weekday initials in the grid's column order ("M T W T F S S").
    public static func weekdayInitials(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % 7] }
    }
}
