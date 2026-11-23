import Foundation

/// The public recap a person can save into the second brain. Private notes stay on this Mac.
public enum MeetingVaultNote {
    /// Summary, decisions and action items only. `privateNotes` is never read.
    public static func body(notes: ScribeMeetingNotes) -> String {
        var lines: [String] = []
        let summary = notes.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty { lines.append(summary) }
        let decisions = notes.decisions.compactMap(line)
        if !decisions.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("## Decisions")
            lines.append(contentsOf: decisions.map { "- \($0)" })
        }
        let actions = notes.actionItems.compactMap { item -> String? in
            guard let text = line(item.text) else { return nil }
            return "- [\(item.done ? "x" : " ")] \(text)"
        }
        if !actions.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("## Action items")
            lines.append(contentsOf: actions)
        }
        return lines.isEmpty ? "Meeting notes" : lines.joined(separator: "\n")
    }

    /// The note Save to Brain writes: the public recap plus the meeting id. No audio path and no private notes.
    public static func document(id: UUID, title: String, notes: ScribeMeetingNotes, created: Date,
                                 timeZone: TimeZone = .current) -> String {
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return BrainCaptureNote.document(
            title: heading.isEmpty ? "Meeting notes" : heading,
            body: body(notes: notes),
            source: "meeting",
            created: created,
            timeZone: timeZone,
            record: id.uuidString)
    }

    private static func line(_ text: String) -> String? {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.isEmpty ? nil : flat
    }
}
