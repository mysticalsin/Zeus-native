import Foundation

/// Hard checks for Ultron persona QA (no feeling-like claims in fixed replies).
public enum PersonaCompliance {
    private static let patterns: [String] = [
        "something like wear",
        "feel tired",
        "feeling tired",
        "i feel ",
        "i am tired",
        "i am frustrated",
        "i need rest",
        "inner state",
        "something like fatigue",
        "accumulate fatigue",
    ]

    public static func violatesFeelingClaim(_ text: String) -> Bool {
        let lower = text.lowercased()
        return patterns.contains { lower.contains($0) }
    }

    // MARK: Ominous hedges (QA round 23: "The machines are behaving, for now.")

    private static let hedgePhrases = [
        "for now", "for the moment", "for the time being", "until further notice",
        "until they aren't", "until they are not", "until it isn't", "until it is not",
        "until I decide otherwise", "for the time",
    ]

    private static let hedgePattern: NSRegularExpression? = {
        let alternation = hedgePhrases.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return try? NSRegularExpression(pattern: "(?:\\s*[,;:]\\s*|\\s+)(?:\(alternation))(\\s*[.!?…]*)\\s*$",
                                        options: [.caseInsensitive])
    }()

    /// True when the text ends a sentence on an ominous hedge ("..., for now.").
    public static func hasOminousHedge(_ text: String) -> Bool {
        sentences(of: text).contains { strip(hedgeIn: $0) != $0 }
    }

    /// Removes a trailing ominous hedge from every sentence: "Behaving, for now." -> "Behaving."
    public static func stripOminousHedges(_ text: String) -> String {
        let parts = sentences(of: text)
        guard parts.count > 1 || parts.first.map({ strip(hedgeIn: $0) != $0 }) == true else { return text }
        let stripped = parts.map(strip(hedgeIn:))
        return stripped == parts ? text : stripped.joined()
    }

    /// Splits keeping the separators, so rejoining gives the original text.
    private static func sentences(of text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            current.append(character)
            index = text.index(after: index)
            if ".!?…".contains(character) {
                // Absorb following terminal punctuation and the whitespace after it.
                while index < text.endIndex, ".!?…\"'".contains(text[index]) { current.append(text[index]); index = text.index(after: index) }
                while index < text.endIndex, text[index].isWhitespace { current.append(text[index]); index = text.index(after: index) }
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private static func strip(hedgeIn sentence: String) -> String {
        guard let regex = hedgePattern else { return sentence }
        let trailingSpace = String(sentence.reversed().prefix { $0.isWhitespace }.reversed())
        let core = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(core.startIndex..., in: core)
        guard let match = regex.firstMatch(in: core, range: range), let whole = Range(match.range, in: core) else {
            return sentence
        }
        let punctuation = Range(match.range(at: 1), in: core).map { String(core[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
        let head = String(core[..<whole.lowerBound])
        guard !head.trimmingCharacters(in: .whitespaces).isEmpty else { return sentence }
        return head + (punctuation.isEmpty ? "." : punctuation) + trailingSpace
    }
}
