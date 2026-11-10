import Foundation

/// "What you have today" from a Markdown second brain, read-only: the daily note, open tasks
/// due today or overdue (Tasks `📅 2026-10-31`, Dataview `due:: 2026-10-31`, `[due:: ...]`),
/// open tasks in today's daily note, and meeting notes named for today.
/// Folders starting with "_" or "." (indexes, relays, agent state) and archives are skipped.
public struct TodayTask: Equatable, Sendable, Identifiable {
    public var id: String { "\(file):\(line)" }
    public var title: String
    public var due: String?
    public var overdue: Bool
    /// Path relative to the vault.
    public var file: String
    public var line: Int

    public init(title: String, due: String?, overdue: Bool, file: String, line: Int) {
        self.title = title; self.due = due; self.overdue = overdue; self.file = file; self.line = line
    }
}

public struct TodayNote: Equatable, Sendable, Identifiable {
    public var id: String { file }
    public var title: String
    public var file: String

    public init(title: String, file: String) { self.title = title; self.file = file }
}

public struct TodaySummary: Equatable, Sendable {
    public var day: String
    public var dailyNote: String?
    public var tasks: [TodayTask] = []
    public var meetings: [TodayNote] = []
    public var scannedFiles = 0

    public init(day: String, dailyNote: String? = nil, tasks: [TodayTask] = [], meetings: [TodayNote] = []) {
        self.day = day; self.dailyNote = dailyNote; self.tasks = tasks; self.meetings = meetings
    }

    public var isEmpty: Bool { dailyNote == nil && tasks.isEmpty && meetings.isEmpty }
}

public enum TodayScanner {
    public static let maxFiles = 6000
    public static let maxBytes = 400_000
    static let skipFolders: Set<String> = ["04_Archives", "Archive", "Archives", "node_modules", "build"]

    public static func scan(vault: URL, now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian),
                            daily: DailyNoteConfig? = nil) -> TodaySummary {
        let day = TodoQuickAdd.dayString(now, calendar: calendar)
        var summary = TodaySummary(day: day)
        let config = daily ?? DailyNoteConfig.read(vault: vault)
        let dailyRelative = config.relativePath(for: now, calendar: calendar)
        if let dailyURL = BrainConnection.inside(vault, dailyRelative),
           FileManager.default.fileExists(atPath: dailyURL.path) {
            summary.dailyNote = dailyRelative
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return summary }
        var seen = 0
        for case let url as URL in walker {
            guard let relative = VaultPathBoundary.relativePath(of: url, in: vault) else {
                walker.skipDescendants()
                continue
            }
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if name.hasPrefix("_") || name.hasPrefix(".") || skipFolders.contains(name) { walker.skipDescendants() }
                continue
            }
            guard url.pathExtension.lowercased() == "md", (values?.fileSize ?? 0) <= maxBytes else { continue }
            seen += 1
            if seen > maxFiles { break }
            let isDaily = relative == dailyRelative
            let isMeeting = relative.lowercased().contains("meeting") && name.contains(day)
            if isMeeting {
                summary.meetings.append(TodayNote(title: url.deletingPathExtension().lastPathComponent, file: relative))
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8), text.contains("- [ ]") || text.contains("* [ ]") else { continue }
            for (index, raw) in text.components(separatedBy: "\n").enumerated() {
                guard let task = TodoMarkdown.parse(line: raw), !task.done else { continue }
                var title = task.title
                var due = task.due
                if due == nil, let found = dataviewDue(in: title) { due = found.day; title = found.title }
                let overdue = due.map { $0 < day } ?? false
                if isDaily || due == day || overdue {
                    summary.tasks.append(TodayTask(title: title, due: due, overdue: overdue, file: relative, line: index + 1))
                }
            }
        }
        summary.scannedFiles = min(seen, maxFiles)
        summary.tasks.sort { ($0.overdue ? 0 : 1, $0.due ?? day) < ($1.overdue ? 0 : 1, $1.due ?? day) }
        return summary
    }

    /// `due:: 2026-10-31` or `[due:: 2026-10-31]`.
    static func dataviewDue(in title: String) -> (day: String, title: String)? {
        guard let range = title.range(of: "due::") else { return nil }
        let after = title[range.upperBound...].trimmingCharacters(in: .whitespaces)
        let day = String(after.prefix(10))
        guard TodoMarkdown.isDay(day) else { return nil }
        var start = range.lowerBound
        if start > title.startIndex, title[title.index(before: start)] == "[" { start = title.index(before: start) }
        var clean = String(title[..<start]) + after.dropFirst(10)
        if clean.hasPrefix("]") { clean.removeFirst() }
        clean = clean.replacingOccurrences(of: " ]", with: "").replacingOccurrences(of: "]", with: "")
        return (day, clean.trimmingCharacters(in: .whitespaces))
    }
}

/// The spoken daily brief: short sentences, at most three items per group.
public enum DailyBrief {
    public static func text(summary: TodaySummary, events: [(title: String, time: String)], zeusTodos: [TodoItem],
                            weather: String? = nil) -> String {
        var lines: [String] = []
        if events.isEmpty {
            lines.append("Your calendar is clear today.")
        } else {
            let first = events.prefix(3).map { "\($0.title) at \($0.time)" }.joined(separator: ", ")
            lines.append("You have \(events.count) \(events.count == 1 ? "event" : "events") today: \(first)\(events.count > 3 ? ", and more" : "").")
        }
        // Due today or overdue. An undated to-do is not due.
        let todayTodos = zeusTodos.filter { todo in
            guard !todo.done, let due = todo.due, !due.isEmpty else { return false }
            return due <= summary.day
        }
        let titles = todayTodos.map(\.title) + summary.tasks.map(\.title)
        if titles.isEmpty {
            lines.append("No to-dos are due.")
        } else {
            let overdue = todayTodos.filter { ($0.due ?? summary.day) < summary.day }.count + summary.tasks.filter(\.overdue).count
            lines.append("\(titles.count) \(titles.count == 1 ? "to-do" : "to-dos")\(overdue > 0 ? ", \(overdue) overdue" : ""): \(titles.prefix(3).joined(separator: ", "))\(titles.count > 3 ? ", and more" : "").")
        }
        if !summary.meetings.isEmpty {
            lines.append("Meeting notes for today: \(summary.meetings.prefix(3).map(\.title).joined(separator: ", ")).")
        }
        if let weather { lines.append(weather) }
        return lines.joined(separator: " ")
    }
}

/// The one place ZEUS may write in a second brain: `00_Inbox/from-zeus/`.
public enum BrainInbox {
    public static let folder = "00_Inbox/from-zeus"

    public static func url(vault: URL, name: String) -> URL? {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "..", with: "-")
        guard !safe.isEmpty else { return nil }
        let target = vault.appendingPathComponent(folder).appendingPathComponent(safe).standardizedFileURL
        let allowed = vault.appendingPathComponent(folder).standardizedFileURL.path + "/"
        return target.path.hasPrefix(allowed) && VaultPathBoundary.relativePath(of: target, in: vault) != nil ? target : nil
    }

    @discardableResult
    public static func write(_ text: String, vault: URL, name: String) throws -> URL {
        guard let target = url(vault: vault, name: name) else { throw CocoaError(.fileWriteInvalidFileName) }
        return try ProfileNoteWriter.write(text, to: target, vault: vault)
    }
}
