import Foundation

/// Dates as ZEUS shows them: Gregorian with the person's locale for names by default, so a Persian-region
/// Mac does not mix "Aban" with English weekdays. Settings › General can opt in to the Mac's own calendar
/// (`dates.followSystemCalendar` = true).
public enum ZeusDates {
    public static let followSystemKey = "dates.followSystemCalendar"

    public static func followsSystem(_ defaults: UserDefaults = .standard) -> Bool {
        // Unset means Gregorian. Only an explicit true follows the Mac's calendar.
        defaults.object(forKey: followSystemKey) != nil && defaults.bool(forKey: followSystemKey)
    }

    /// The calendar for display and for day math in the UI.
    public static func calendar(followSystem: Bool = followsSystem(), base: Calendar = .current) -> Calendar {
        guard !followSystem else { return base }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale(followSystem: false, base: base.locale ?? .current)
        calendar.timeZone = base.timeZone
        calendar.firstWeekday = base.firstWeekday
        return calendar
    }

    /// The person's locale with its calendar forced to Gregorian (unless following the system).
    public static func locale(followSystem: Bool = followsSystem(), base: Locale = .current) -> Locale {
        guard !followSystem else { return base }
        var components = Locale.Components(locale: base)
        components.calendar = .gregorian
        return Locale(components: components)
    }

    /// Start of a format chain: `date.formatted(ZeusDates.style.weekday(.wide))`.
    public static var style: Date.FormatStyle {
        let follow = followsSystem()
        return Date.FormatStyle(locale: locale(followSystem: follow), calendar: calendar(followSystem: follow))
    }

    /// A localized template such as "EEEEdMMMM" in the ZEUS calendar.
    public static func string(_ date: Date, template: String, followSystem: Bool = followsSystem(), base: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale(followSystem: followSystem, base: base)
        formatter.calendar = followSystem ? base.calendar : calendar(followSystem: false)
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    public static func day(of date: Date) -> Int { calendar().component(.day, from: date) }
}
