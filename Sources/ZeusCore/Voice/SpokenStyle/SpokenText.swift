import Foundation

enum SpokenText {
    static func collapse(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for character in text {
            if character.isWhitespace {
                if !result.isEmpty { pendingSpace = true }
                continue
            }
            if ".,;:!?".contains(character) {
                pendingSpace = false
            }
            if pendingSpace {
                result.append(" ")
                pendingSpace = false
            }
            result.append(character)
        }
        return result
    }

    static func words(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).filter { !$0.isEmpty }.count
    }

    static func capitalizingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }

    static func startsToken(_ text: String, at index: String.Index) -> Bool {
        guard index > text.startIndex else { return true }
        let previous = text[text.index(before: index)]
        return !previous.isLetter && !previous.isNumber
    }

    static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            preconditionFailure("SpokenStyle pattern failed to compile: \(error.localizedDescription)")
        }
    }

    static func rewrite(
        _ text: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        _ body: (NSTextCheckingResult, String) -> String
    ) -> String {
        let expression = regex(pattern, options: options)
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        if matches.isEmpty { return text }
        var result = ""
        var cursor = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            result += text[cursor..<range.lowerBound]
            result += body(match, text)
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }

    static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String {
        guard index < match.numberOfRanges, let range = Range(match.range(at: index), in: text) else { return "" }
        return String(text[range])
    }

    /// The captures of a match anchored at the start of `rest`. Group 0 is the whole match.
    /// Nil when the pattern does not match there.
    static func prefixMatch(_ pattern: String, in rest: String) -> [String]? {
        let expression = regex(pattern)
        let range = NSRange(rest.startIndex..., in: rest)
        guard let match = expression.firstMatch(in: rest, range: range),
              match.range.location == 0 else { return nil }
        var groups: [String] = []
        for index in 0..<match.numberOfRanges {
            if let groupRange = Range(match.range(at: index), in: rest) {
                groups.append(String(rest[groupRange]))
            } else {
                groups.append("")
            }
        }
        return groups
    }
}
