import Foundation

/// Whether equation text has a body.
/// This type does not measure a font, does not draw, and does not run a TeX lexer.
public enum ExplanationEquationGeometryBox {
    /// Spaces and line breaks, named as scalars. U+200B is not a member. Linux
    /// `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so equation text is not asked of that set.
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

    /// True when `text` has a scalar outside `blankScalars`. Empty is not equation text.
    /// A zero-width space is equation text.
    public static func hasEquationText(_ text: String) -> Bool {
        !trimmed(text).isEmpty
    }
}
