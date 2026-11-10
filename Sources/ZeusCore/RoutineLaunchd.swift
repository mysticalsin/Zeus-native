import Foundation

/// Writes LaunchAgent plists for scheduled routines. Tests use `FakeLaunchctl`, never real launchctl.
public enum RoutineLaunchAgent {
    public static let labelPrefix = "app.zeus.mac.routine."

    public static func label(for routine: Routine) -> String { labelPrefix + routine.id.uuidString.lowercased() }

    public static func plist(routine: Routine, zeusBinary: String, uid: Int = Int(getuid())) -> [String: Any] {
        var interval: [String: Any] = [
            "Hour": routine.schedule.hour,
            "Minute": routine.schedule.minute,
        ]
        if routine.schedule.days == .weekdays {
            interval["Weekday"] = [2, 3, 4, 5, 6]
        }
        return [
            "Label": label(for: routine),
            "ProgramArguments": [zeusBinary, "routine-run", routine.id.uuidString],
            "StartCalendarInterval": interval,
            "StandardOutPath": "/tmp/zeus-routine-\(routine.id.uuidString).log",
            "StandardErrorPath": "/tmp/zeus-routine-\(routine.id.uuidString).err",
            "EnvironmentVariables": ["ZEUS_ROUTINE_UID": "\(uid)"],
        ]
    }

    public static func writePlist(routine: Routine, agentsDirectory: URL, zeusBinary: String) throws -> URL {
        let url = agentsDirectory.appendingPathComponent("\(label(for: routine)).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: plist(routine: routine, zeusBinary: zeusBinary), format: .xml, options: 0)
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// In-memory launchctl for unit tests and silent eval.
public final class FakeLaunchctl: @unchecked Sendable {
    public private(set) var agentsDirectory: URL
    public private(set) var bootstrapped: Set<String> = []
    public private(set) var fireLog: [(label: String, date: Date)] = []

    public init(agentsDirectory: URL) { self.agentsDirectory = agentsDirectory }

    public func bootstrap(label: String, plistURL: URL) throws {
        _ = plistURL
        bootstrapped.insert(label)
    }

    public func bootout(label: String) { bootstrapped.remove(label) }

    public func simulateFire(label: String, at date: Date) { fireLog.append((label, date)) }
}

/// Prevents the same calendar slot from running twice after an app relaunch.
public struct RoutineRelaunchGuard: Equatable, Sendable {
    public private(set) var lastFiredSlot: [UUID: Date] = [:]

    public init() {}

    public mutating func shouldRun(routine: Routine, scheduled: Date, calendar: Calendar = .current) -> Bool {
        guard let previous = lastFiredSlot[routine.id] else { return true }
        return calendar.compare(previous, to: scheduled, toGranularity: .minute) != .orderedSame
    }

    public mutating func markRan(routineID: UUID, scheduled: Date) {
        lastFiredSlot[routineID] = scheduled
    }
}

public enum RoutineVoiceParse {
    public struct Parsed: Equatable, Sendable {
        public var name: String
        public var prompt: String
        public var schedule: RoutineSchedule
    }

    /// "every weekday at 8, summarize my calendar"
    public static func parse(_ text: String) -> Parsed? {
        var utterance = Utterance(text)
        utterance.stripFiller()
        let joined = utterance.words.joined(separator: " ")
        guard joined.contains("every") || joined.contains("weekday") || joined.contains("daily") else { return nil }
        let days: RoutineSchedule.Days = joined.contains("weekday") ? .weekdays : .daily
        let hour = joined.range(of: #"\bat\s+(\d{1,2})\b"#, options: .regularExpression)
            .flatMap { Int(joined[$0].split(separator: " ").last ?? "") } ?? 8
        let comma = joined.firstIndex(of: ",").map { joined.index(after: $0) } ?? joined.startIndex
        let prompt = String(joined[comma...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return nil }
        let name = prompt.split(separator: " ").prefix(4).joined(separator: " ")
        return Parsed(name: name.capitalized, prompt: prompt, schedule: RoutineSchedule(days: days, hour: hour, minute: 0))
    }
}
