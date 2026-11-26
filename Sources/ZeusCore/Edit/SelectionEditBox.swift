import Foundation

/// How a spoken selection edit is planned: the reply, the insert, and the shorter cut.
/// This type does not read a screen, a pointer, a clock, or a stored setting.
public enum SelectionEditBox {
    /// Spaces and line breaks, named as scalars. U+200B is not a member. Linux
    /// `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so a phrase is not asked of that set.
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

    /// A command that must start with its lead does not match when U+200B is in front.
    /// "shorter" is contained, so a zero-width space in front still selects that cut.
    /// An insert or a reply keeps a zero-width space in the body. A body of only named blanks
    /// is empty: an insert is refused, and a reply keeps the selection.
    public static func plan(utterance: String, selection: String) -> SelectionEdit? {
        let trimmedUtterance = trimmed(utterance)
        let lower = trimmedUtterance.lowercased()
        if lower.hasPrefix("reply to this") {
            let rest = trimmedUtterance.dropFirst("reply to this".count)
            var body = trimmed(String(rest))
            if body.hasPrefix(".") {
                body = trimmed(String(body.dropFirst()))
            }
            if body.isEmpty { body = selection }
            return SelectionEdit(kind: .draft, before: selection, after: body, sends: false)
        }
        if lower.hasPrefix("insert ") {
            let body = trimmed(String(trimmedUtterance.dropFirst("insert ".count)))
            guard !body.isEmpty else { return nil }
            return SelectionEdit(kind: .insert, before: selection, after: body, sends: false)
        }
        if lower.contains("shorter") {
            return SelectionEdit(kind: .replace, before: selection, after: shorter(selection), sends: false)
        }
        return nil
    }

    /// Keeps the first half of the words. A single word is returned unchanged.
    /// Word breaks use `Character.isWhitespace`, which does not treat U+200B as blank.
    public static func shorter(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else { return text }
        return words.prefix(max(words.count / 2, 1)).joined(separator: " ")
    }
}
