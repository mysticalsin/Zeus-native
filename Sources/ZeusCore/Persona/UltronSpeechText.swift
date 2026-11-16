import Foundation

/// Spoken Ultron replies carry no ellipses: a TTS voice reads "..." as a long, breathy gap.
public enum UltronSpeechText {
    private static let ellipsis = try? NSRegularExpression(pattern: "\\s*(?:\\.{3,}|\u{2026})+\\s*")

    private static let closers: Set<Character> = [")", "]", "}", ">", "\"", "'", "\u{201D}", "\u{2019}", "\u{00BB}", "?", "!", ".", ",", ";", ":"]
    private static let openers: Set<Character> = ["(", "[", "{", "<"]

    /// Replaces "..." and the single "…" with a comma, or a period when the sentence ends there
    /// (end of text, or a capital letter follows). No mark when punctuation or a closing quote follows
    /// ("Hmm...?" becomes "Hmm?"). Number ranges ("1...5"), code-like tokens ("a...b") and a bracketed
    /// "[...]" are left as written.
    public static func sanitize(_ text: String) -> String {
        guard let ellipsis, text.contains(".") || text.contains("\u{2026}") else { return text }
        var result = text
        let matches = ellipsis.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let matched = result[range]
            let before = result[..<range.lowerBound]
            let after = result[range.upperBound...]
            if before.isEmpty { result.replaceSubrange(range, with: ""); continue }
            if let last = before.last, openers.contains(last) { continue }
            let tight = !matched.contains(where: \.isWhitespace)
            if tight, let last = before.last, let first = after.first, last.isLetter || last.isNumber,
               first.isLetter || first.isNumber { continue }
            let next = after.first
            let beforeEnd = before.last
            let mark: String
            if let beforeEnd, ".!?,;:".contains(beforeEnd) || next.map(closers.contains) == true {
                mark = ""
            } else {
                mark = (next.map(\.isUppercase) ?? true) ? "." : ","
            }
            let spaced = !after.isEmpty && !(next.map(closers.contains) ?? false)
            result.replaceSubrange(range, with: mark + (spaced ? " " : ""))
        }
        return result
    }

    /// The text to hand a voice: sanitized for the Ultron personality, untouched for plain.
    public static func prepared(_ text: String, personality: ZeusPersonality) -> String {
        personality == .ultron ? sanitize(text) : text
    }
}
