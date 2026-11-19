import Foundation

/// The Mac's own calendars. EventKit is the only reader. Nothing is sent off the Mac.
public enum LocalCalendarAccess {
    public enum Status: Equatable, Sendable {
        case notAsked, allowed, denied, restricted
    }

    public static func map(fullAccess: Bool, denied: Bool, restricted: Bool, asked: Bool) -> Status {
        if restricted { return .restricted }
        if fullAccess { return .allowed }
        if denied { return .denied }
        return asked ? .denied : .notAsked
    }

    /// True when one of the calendars EventKit can see is an Exchange or Outlook account
    /// the person already added to the Mac.
    public static func outlookVisible(calendarSources: [String]) -> Bool {
        calendarSources.contains { source in
            let name = source.lowercased()
            return name == "outlook" || name == "exchange" || name.hasPrefix("outlook ") || name.hasPrefix("exchange ")
        }
    }

    public static func outlookReport(calendarSources: [String]) -> String {
        if outlookVisible(calendarSources: calendarSources) {
            return "Outlook is visible through the Mac's calendars."
        }
        return "Outlook's calendar is not in the Mac's calendars. Add that account in System Settings, Internet Accounts. Zeus does not connect to Outlook itself."
    }

    public static let permissionsNote = "Agenda from the calendars on this Mac. Read only. Asked only when you turn the agenda on."
}

/// Outlook for Mac, both the current app and the older one, does not offer a public calendar
/// script that Zeus can rely on. The current app has no supported calendar dictionary. The older
/// app's dictionary is not a stable public API. Zeus does not script Outlook.
public enum OutlookCalendarBridge {
    public static let usesAppleScript = false
    public static let finding =
        "Outlook is not scripted. Calendars the Mac already has, including an Exchange account added in System Settings, are read with EventKit. A calendar Outlook keeps to itself is reported as not visible."
}
