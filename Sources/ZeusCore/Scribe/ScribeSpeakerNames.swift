import Foundation

/// Renaming and merging speakers in a finished meeting, and the text exports that carry the names. Pure: the
/// recap, the saved file, the statistics and the copied or exported text all read the same relabelled segments.
public enum ScribeSpeakerNames {
    /// Who `name` means among `segments`: "You" is the person at the keyboard, a name already used by another
    /// speaker (any capitalisation) is that speaker, anything else is a new participant name. Nil for a blank name.
    public static func target(for name: String, in segments: [ScribeTranscriptSegment]) -> ScribeSpeaker? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let wanted = key(trimmed)
        if wanted == key("You") { return .you }
        for segment in segments {
            if case .participant(let existing) = segment.speaker, key(existing) == wanted { return segment.speaker }
        }
        return .participant(trimmed)
    }

    /// Every segment of `speaker` now belongs to whoever `name` means. The person at the keyboard keeps "You":
    /// renaming them does nothing. Naming a speaker with another speaker's name merges the two.
    public static func rename(
        _ speaker: ScribeSpeaker, to name: String, in segments: [ScribeTranscriptSegment]
    ) -> [ScribeTranscriptSegment] {
        guard speaker != .you, let target = target(for: name, in: segments), target != speaker else { return segments }
        return segments.map { segment in
            guard segment.speaker == speaker else { return segment }
            var changed = segment
            changed.speaker = target
            return changed
        }
    }

    /// Case, accent and spacing differences do not make two names two people.
    public static func key(_ name: String) -> String { ScribeAttendeeNames.key(name) }
}

/// Transcript text for the clipboard and for Markdown files. Final, non-empty segments only.
public enum ScribeTranscriptExport {
    /// One block per segment: the speaker in bold with the time, then the words.
    public static func markdown(title: String, segments: [ScribeTranscriptSegment]) -> String {
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = ["# \(heading.isEmpty ? "Meeting notes" : heading)", ""]
        for segment in readable(segments) {
            lines.append("**\(segment.speaker.displayName)** (\(ScribeSpeakerStats.format(segment.start)))")
            lines.append(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// "Name: words", one line per segment, for pasting into a message.
    public static func plainText(segments: [ScribeTranscriptSegment]) -> String {
        readable(segments)
            .map { "\($0.speaker.displayName): \($0.text.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")
    }

    private static func readable(_ segments: [ScribeTranscriptSegment]) -> [ScribeTranscriptSegment] {
        segments.filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
