import Foundation

/// Key-shaped text removed before a line is logged. The function is pure: the same
/// input always returns the same string, and the input is left untouched.
public enum PrivateLogText {
    public static let mask = "[redacted]"

    /// Replaces `sk-`, `xi-` and `AIza` tokens, and long base64 or hex runs, with `[redacted]`.
    public static func redact(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let ranges = merged(prefixMatches(in: text) + runMatches(in: text, minimum: 32, isMember: isHex, allowPadding: false)
            + runMatches(in: text, minimum: 40, isMember: isBase64, allowPadding: true))
        guard !ranges.isEmpty else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var cursor = text.startIndex
        for range in ranges {
            result.append(contentsOf: text[cursor..<range.lowerBound])
            result.append(mask)
            cursor = range.upperBound
        }
        result.append(contentsOf: text[cursor...])
        return result
    }

    // MARK: Matches

    private static let prefixes = ["sk-", "xi-", "AIza"]
    /// Characters that continue a prefixed token after the prefix itself.
    private static let minimumSuffix = 8

    private static func prefixMatches(in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            let previous: Character? = index == text.startIndex ? nil : text[text.index(before: index)]
            if isBoundary(previous) {
                var consumed: Range<String.Index>?
                for prefix in prefixes where text[index...].hasPrefix(prefix) {
                    let body = text.index(index, offsetBy: prefix.count)
                    var end = body
                    var extra = 0
                    while end < text.endIndex, isKeyBody(text[end]) {
                        extra += 1
                        end = text.index(after: end)
                    }
                    if extra >= minimumSuffix {
                        consumed = index..<end
                        break
                    }
                }
                if let consumed {
                    found.append(consumed)
                    index = consumed.upperBound
                    continue
                }
            }
            index = text.index(after: index)
        }
        return found
    }

    private static func runMatches(in text: String, minimum: Int, isMember: (Character) -> Bool, allowPadding: Bool) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard isMember(text[index]) else {
                index = text.index(after: index)
                continue
            }
            let start = index
            var count = 0
            while index < text.endIndex, isMember(text[index]) {
                count += 1
                index = text.index(after: index)
            }
            guard count >= minimum else { continue }
            var end = index
            if allowPadding {
                var pads = 0
                while end < text.endIndex, pads < 2, text[end] == "=" {
                    pads += 1
                    end = text.index(after: end)
                }
            }
            found.append(start..<end)
        }
        return found
    }

    /// Earlier, then longer, wins. A prefixed token and the hex inside it become one mask.
    private static func merged(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        let ordered = ranges.sorted {
            if $0.lowerBound != $1.lowerBound { return $0.lowerBound < $1.lowerBound }
            return $0.upperBound > $1.upperBound
        }
        var accepted: [Range<String.Index>] = []
        for range in ordered {
            if let last = accepted.last, range.lowerBound < last.upperBound { continue }
            accepted.append(range)
        }
        return accepted
    }

    // MARK: Characters

    private static func isBoundary(_ character: Character?) -> Bool {
        guard let character, let value = character.asciiValue else { return true }
        switch value {
        case UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "_"):
            return false
        default:
            return true
        }
    }

    private static func isKeyBody(_ character: Character) -> Bool {
        guard let value = character.asciiValue else { return false }
        switch value {
        case UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "_"),
             UInt8(ascii: "-"):
            return true
        default:
            return false
        }
    }

    private static func isHex(_ character: Character) -> Bool {
        guard let value = character.asciiValue else { return false }
        switch value {
        case UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "a")...UInt8(ascii: "f"),
             UInt8(ascii: "A")...UInt8(ascii: "F"):
            return true
        default:
            return false
        }
    }

    private static func isBase64(_ character: Character) -> Bool {
        guard let value = character.asciiValue else { return false }
        switch value {
        case UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "+"),
             UInt8(ascii: "/"):
            return true
        default:
            return false
        }
    }
}
