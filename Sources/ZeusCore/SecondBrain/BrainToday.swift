import Foundation

/// "What do I have today?" straight from the second brain: open Markdown checkboxes, with
/// anything dated today first, then high priority, never the blocked ones. Read-only.
public struct BrainTask: Equatable, Identifiable, Sendable {
    public var title: String
    public var project: String
    public var dueToday: Bool
    public var highPriority: Bool
    public var file: String
    public var id: String { file + "#" + title }

    public init(title: String, project: String, dueToday: Bool, highPriority: Bool, file: String) {
        self.title = title; self.project = project; self.dueToday = dueToday; self.highPriority = highPriority; self.file = file
    }
}

public enum BrainToday {
    /// The connected vault, or a common default location when nothing is connected yet.
    public static func defaultRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        for name in ["Documents/brain", "Documents/Brain", "Documents/Second Brain", "Documents/Obsidian"] {
            let url = home.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return url }
        }
        return nil
    }

    public static func scan(root: URL, today: Date = Date(), limit: Int = 8, maxFiles: Int = 600) -> [BrainTask] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Notes carry ISO (Gregorian) dates even when the Mac runs another calendar.
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let stamp = formatter.string(from: today)
        let skip: Set<String> = ["node_modules", "build", "04_Archives", "Archive", "Archives"]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var tasks: [BrainTask] = []
        var files = 0
        for case let url as URL in walker {
            guard let relative = VaultPathBoundary.relativePath(of: url, in: root) else {
                walker.skipDescendants()
                continue
            }
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                if name.hasPrefix("_") || skip.contains(name) || walker.level > 4 { walker.skipDescendants() }
                continue
            }
            guard url.pathExtension.lowercased() == "md", (values?.fileSize ?? 0) < 512_000 else { continue }
            files += 1
            if files > maxFiles { break }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let project = projectName(relative)
            for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix("- [ ]") || line.hasPrefix("* [ ]") else { continue }
                let body = String(line.dropFirst(5))
                let lower = body.lowercased()
                if lower.contains("#blocked") || lower.contains("#someday") { continue }
                let dueToday = body.contains(stamp) || lower.contains("#today")
                let high = lower.contains("#priority/high") || lower.contains("⏫") || lower.contains("🔺") || lower.contains("#p1")
                let title = clean(body)
                guard !title.isEmpty else { continue }
                tasks.append(BrainTask(title: title, project: project, dueToday: dueToday, highPriority: high, file: relative))
            }
        }
        let ranked = tasks.enumerated().sorted { a, b in
            let ra = (a.element.dueToday ? 0 : 2) + (a.element.highPriority ? 0 : 1)
            let rb = (b.element.dueToday ? 0 : 2) + (b.element.highPriority ? 0 : 1)
            return ra == rb ? a.offset < b.offset : ra < rb
        }.map(\.element)
        return Array(ranked.prefix(limit))
    }

    static func projectName(_ relative: String) -> String {
        let parts = relative.split(separator: "/").map(String.init)
        if parts.count >= 2, parts[0].range(of: #"^\d\d_"#, options: .regularExpression) != nil { return parts.count > 2 ? parts[1] : parts[0].replacingOccurrences(of: #"^\d\d_"#, with: "", options: .regularExpression) }
        if parts.count >= 2 { return parts[0] }
        return (parts.first ?? relative).replacingOccurrences(of: ".md", with: "")
    }

    /// Drops ids, tags, dates and emoji markers so the line reads like a to-do.
    static func clean(_ body: String) -> String {
        var text = body
        text = text.replacingOccurrences(of: #"^\s*[A-Z]+-\d+\s+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s#[\w/-]+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[📅⏳🛫✅⏫🔺🔼🔽]\s*\d{4}-\d{2}-\d{2}"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[⏫🔺🔼🔽]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[\[([^\]|]+)\|?([^\]]*)\]\]"#, with: "$1", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespaces)
    }
}
