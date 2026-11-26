import Foundation

/// Edge trim for a call-window participant name.
/// This type does not read a screen, a pointer, a clock, or a stored setting.
public enum MeetingSpeakerLabelsBox {
    /// Spaces and line breaks, named as scalars. U+200B is not a member. Linux
    /// `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so a name is not asked of that set.
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

    /// Punctuation a call window leaves on the edges of a name. U+200B is not a member.
    public static let edgePunctuation: Set<Unicode.Scalar> = [
        ",", ";", ":", "-", "|", "(", ")", "[", "]",
        "\u{2013}", "\u{2014}", "\u{2022}", "\u{00B7}",
    ]

    /// Leading and trailing blanks and edge punctuation only. A zero-width space stays.
    public static func trimmed(_ text: String) -> String {
        let edge = blankScalars.union(edgePunctuation)
        let scalars = text.unicodeScalars
        var start = scalars.startIndex
        var end = scalars.endIndex
        while start < end, edge.contains(scalars[start]) {
            start = scalars.index(after: start)
        }
        while end > start {
            let previous = scalars.index(before: end)
            if edge.contains(scalars[previous]) {
                end = previous
            } else {
                break
            }
        }
        return String(String.UnicodeScalarView(scalars[start..<end]))
    }
}
