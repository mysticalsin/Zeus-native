import Foundation

/// Quiet-hours and silent-test behaviour for the Settings > Voice Test button (K2).
public enum QuietHoursVoiceTest {
    /// America/Sao_Paulo quiet window 21:00 to 09:30, or `ZEUS_SILENT_TESTS=1`.
    public static func shouldWriteToFileOnly(now: Date = Date(), env: [String: String] = ProcessInfo.processInfo.environment,
                                             calendar: Calendar = brtCalendar()) -> Bool {
        if env["ZEUS_SILENT_TESTS"] == "1" { return true }
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let minutes = hour * 60 + minute
        // 21:00 (1260) through midnight, and midnight through 09:30 (570).
        if minutes >= 21 * 60 { return true }
        if minutes < 9 * 60 + 30 { return true }
        return false
    }

    public static func outputDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Zeus/VoiceTest", isDirectory: true)
    }

    public static func brtCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
        return cal
    }
}
