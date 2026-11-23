import Foundation

/// Who is allowed to raise the system prompt for full calendar access.
public enum CalendarAccessCaller: String, Sendable, CaseIterable {
    case permissionsDesk
    case proactiveBrief
    case topBar
    case agendaToggle
}

/// Full calendar access is read access on this Mac. It is asked only when the agenda is turned on.
public enum CalendarAccessPolicy {
    public static func mayRequestFullAccess(_ caller: CalendarAccessCaller) -> Bool {
        caller == .agendaToggle
    }

    /// Asks only when this caller may, and never when access is already granted.
    public static func requestFullAccess(
        from caller: CalendarAccessCaller,
        alreadyGranted: Bool,
        ask: () async -> Bool
    ) async -> Bool {
        if alreadyGranted { return true }
        guard mayRequestFullAccess(caller) else { return false }
        return await ask()
    }

    public static let permissionsNote =
        "Agenda from the calendars on this Mac. Read only. Asked only when you turn the agenda on."
}
