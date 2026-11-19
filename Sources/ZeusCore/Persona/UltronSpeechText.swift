import Foundation

/// Spoken Ultron replies carry no ellipses: a TTS voice reads "..." as a long, breathy gap.
public enum UltronSpeechText {
    private static let ellipsis = try? NSRegularExpression(pattern: "\\s*(?:\\.{3,}|\u{2026})+\\s*")

    private static let closers: Set<Character> = [")", "]", "}", ">", "\"", "'", "\u{201D}", "\u{2019}", "\u{00BB}", "?", "!", ".", ",", ";", ":"]
    private static let openers: Set<Character> = ["(", "[", "{", "<"]

    /// Replaces "..." and the single "…" with a comma, or a period when the sentence ends there
    /// (end of text, or a capital letter follows). No mark when punctuation or a closing quote follows
    /// ("Hmm...?" becomes "Hmm?"). Number ranges ("1...5"), single-letter tokens ("a...b") and a bracketed
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
            if tight, keepsTightToken(before: before, after: after) { continue }
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

    /// A tight "x...y" stays as written only for a number range ("1...5") or single-character
    /// tokens ("a...b"); words joined by dots ("Well...yes") are speech and get a pause mark.
    private static func keepsTightToken(before: Substring, after: Substring) -> Bool {
        let left = before.reversed().prefix { $0.isLetter || $0.isNumber }
        let right = after.prefix { $0.isLetter || $0.isNumber }
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left.allSatisfy(\.isNumber) && right.allSatisfy(\.isNumber) { return true }
        return left.count == 1 && right.count == 1
    }

    /// The text to hand a voice: sanitized for the Ultron personality, untouched for plain.
    public static func prepared(_ text: String, personality: ZeusPersonality) -> String {
        personality == .ultron ? sanitize(text) : text
    }
}
