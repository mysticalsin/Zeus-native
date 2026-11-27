import Foundation

/// The words the closed notch shows while dictation is listening.
///
/// An empty partial keeps the waveform. A long partial is cut on a word and ends with an ellipsis.
/// Any other phase keeps the waveform or the progress spinner.
public enum DictationWingText {
    public static let limit = 48

    public static func line(listening: Bool, partial: String) -> String? {
        guard listening else { return nil }
        let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= limit { return trimmed }
        let room = limit - 1
        var current = ""
        for word in trimmed.split(whereSeparator: \.isWhitespace) {
            let piece = String(word)
            let next = current.isEmpty ? piece : current + " " + piece
            if next.count > room { break }
            current = next
        }
        if current.isEmpty { return String(trimmed.prefix(room)) + "…" }
        return current + "…"
    }
}
