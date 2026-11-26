import Foundation

/// Which dictated words are worth writing, and whether a field then holds them.
/// This type does not read a screen, a pointer, a clock, or a stored setting,
/// and it does not write into a field.
public enum WarmFieldInsertBox {
    /// Spaces and line breaks, named as scalars. U+200B is not a member. Linux
    /// `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so a field is not asked of that set.
    public static let blankScalars: Set<Unicode.Scalar> = [
        "\u{0009}", "\u{000A}", "\u{000B}", "\u{000C}", "\u{000D}",
        "\u{0020}",
        "\u{0085}",
        "\u{00A0}",
        "\u{1680}",
        "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}",
        "\u{2005}", "\u{2006}", "\u{2007}", "\u{2008}", "\u{2009}", "\u{200A}",
        "\u{2028}", "\u{2029}",
        "\u{202F}",
        "\u{205F}",
        "\u{3000}",
    ]

    /// Leading and trailing members of `blankScalars` only. A zero-width space stays.
    public static func trimmed(_ text: String) -> String {
        let scalars = text.unicodeScalars
        var start = scalars.startIndex
        var end = scalars.endIndex
        while start < end, blankScalars.contains(scalars[start]) {
            start = scalars.index(after: start)
        }
        while end > start {
            let previous = scalars.index(before: end)
            if blankScalars.contains(scalars[previous]) {
                end = previous
            } else {
                break
            }
        }
        return String(String.UnicodeScalarView(scalars[start..<end]))
    }

    /// Ordered attempts. Empty when the words must not be written.
    /// `current` is kept as given, including a zero-width space already in the field.
    public static func steps(text: String, current: String, valueSettable: Bool,
                             selectedTextSettable: Bool, secure: Bool) -> [WarmFieldInsert.Step] {
        let body = trimmed(text)
        guard !body.isEmpty, !secure else { return [] }
        if current.isEmpty {
            var ordered: [WarmFieldInsert.Step] = []
            if valueSettable { ordered.append(.setValue(body)) }
            if selectedTextSettable { ordered.append(.setSelectedText(body)) }
            return ordered
        }
        var ordered: [WarmFieldInsert.Step] = []
        if selectedTextSettable { ordered.append(.setSelectedText(body)) }
        if valueSettable { ordered.append(.setValue(current + body)) }
        return ordered
    }

    /// The write landed only when the field actually holds the words.
    /// A body of only named blanks is not a landing. A zero-width space is.
    public static func landed(fieldValue: String?, selectedText: String?, expected: String) -> Bool {
        let body = trimmed(expected)
        guard !body.isEmpty else { return false }
        if let fieldValue, fieldValue.contains(body) { return true }
        if let selectedText, selectedText.contains(body) { return true }
        return false
    }
}
