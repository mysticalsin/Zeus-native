import Foundation

/// Spoken punctuation and layout commands before insert (R24 dictation).
public enum SpokenDictationMarkup {
    /// Longer phrases first so "point d'interrogation" is not eaten by "point".
    private static let replacements: [(phrase: String, value: String)] = [
        ("new paragraph", "\n\n"),
        ("nouveau paragraphe", "\n\n"),
        ("nouvelle paragraphe", "\n\n"),
        ("new line", "\n"),
        ("nouvelle ligne", "\n"),
        ("question mark", "?"),
        ("point d'interrogation", "?"),
        ("point d interrogation", "?"),
        ("point d’interrogation", "?"),
        ("full stop", "."),
        ("point final", "."),
        ("comma", ","),
        ("virgule", ","),
    ]

    /// Private marker that splits a phrase so it no longer matches ("literal period" keeps the word).
    private static let keepMarker = "\u{E000}"

    /// Words that, right before "period"/"point", mean it is an ordinary noun ("the main point",
    /// "a period of time", "at this point").
    private static let nounLeaders: Set<String> = [
        "the", "a", "an", "this", "that", "these", "those", "my", "your", "our", "his", "her", "their", "its",
        "of", "in", "for", "at", "to", "on", "per", "one", "each", "every", "whole", "same", "main", "key",
        "good", "great", "valid", "fair", "another", "grace", "trial", "that's", "whats", "what's", "no",
        "any", "some", "sore", "selling", "starting", "turning", "breaking", "decimal", "make", "makes",
        "made", "making", "is", "was", "has", "have", "had", "up", "from", "until", "since", "over",
    ]

    private static let commandFollowers = #"new line|new paragraph|nouvelle ligne|nouveau paragraphe|nouvelle paragraphe"#

    // "period"/"point" are common words, so they only become a full stop at the end of the
    // utterance (or right before a layout command), and never straight after an article,
    // preposition or similar noun-leading word. Say "literal period" to keep the word.
    private static let ambiguousStop = try! NSRegularExpression(
        pattern: #"(?:(\S+)\s+)?\b(?:period|point)\b[.!?]*(?=\s+(?:\#(commandFollowers))\b|\s*$)"#,
        options: .caseInsensitive)
    private static let literalPattern = try! NSRegularExpression(
        pattern: #"\bliteral[ \t]+(\w)"#,
        options: .caseInsensitive)

    public static func apply(_ text: String) -> String {
        var result = protectLiteral(text)
        result = applyAmbiguousStops(result)
        for item in replacements.sorted(by: { $0.phrase.count > $1.phrase.count }) {
            result = replacePhrase(item.phrase, with: item.value, in: result)
        }
        return result.replacingOccurrences(of: keepMarker, with: "")
    }

    /// "literal period" -> "peri<marker>od": the word is written, the cue word is dropped.
    private static func protectLiteral(_ text: String) -> String {
        let ns = text as NSString
        let matches = literalPattern.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var result = text
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result), let first = Range(match.range(at: 1), in: result) else { continue }
            result.replaceSubrange(whole, with: String(result[first]) + keepMarker)
        }
        return result
    }

    private static func applyAmbiguousStops(_ text: String) -> String {
        let ns = text as NSString
        let matches = ambiguousStop.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        var result = text
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result) else { continue }
            var previous: String?
            if match.range(at: 1).location != NSNotFound {
                previous = ns.substring(with: match.range(at: 1))
            }
            let bare = previous?.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if let bare, nounLeaders.contains(bare) { continue }
            guard var kept = previous else {
                result.replaceSubrange(whole, with: ".")
                continue
            }
            while let last = kept.last, last == "," || last == ";" { kept.removeLast() }
            let endsStop = kept.last.map { ".!?".contains($0) } ?? false
            result.replaceSubrange(whole, with: endsStop ? kept : kept + ".")
        }
        return result
    }

    private static func replacePhrase(_ phrase: String, with value: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        // "point de vue" is a phrase, not the French period command.
        let guardSuffix = phrase.caseInsensitiveCompare("point") == .orderedSame ? #"(?!\s+d(?:e|u|es|'|’)\b)"# : ""
        let pattern: String
        if value == "," {
            pattern = #"(?i)(?:^|\s)\#(escaped)\#(guardSuffix)(?=\s|$)"#
        } else if value == "." || value == "?" {
            pattern = #"(?i)\s*\#(escaped)\#(guardSuffix)(?=\s|$)"#
        } else {
            pattern = #"(?i)\s*\#(escaped)\#(guardSuffix)\s*"#
        }
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let replaced = expression.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: value == "," ? ", " : value)
        return replaced.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
    }
}
