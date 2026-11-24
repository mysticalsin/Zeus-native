import Foundation

/// The Markdown for an explicit Save to Brain. A record id is kept only when it is one safe token.
/// Paths, blank ids and anything that would break the front matter are left out. Nothing is written here.
public enum BrainCaptureNote {
    /// One ASCII token of letters, digits and hyphens, at most 80 characters. Nil when the id cannot be kept.
    public static func token(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(trimmed.count),
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        return trimmed
    }

    /// Front matter, title and body. `record` is omitted unless `token` accepts it.
    public static func document(title: String, body: String, source: String, created: Date,
                                 timeZone: TimeZone = .current, record: String? = nil) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        let safeSource = source.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        var lines = [
            "---",
            "type: capture",
            "source: zeus-\(safeSource.isEmpty ? "app" : safeSource)",
        ]
        if let token = token(record) {
            lines.append("record: \(token)")
        }
        lines.append(contentsOf: [
            "created: \(formatter.string(from: created))",
            "tags: [zeus, inbox]",
            "---",
            "",
            "# \(cleanTitle.isEmpty ? "Note from ZEUS" : cleanTitle)",
            "",
            body.trimmingCharacters(in: .whitespacesAndNewlines),
            "",
        ])
        return lines.joined(separator: "\n")
    }
}
