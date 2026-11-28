import Foundation

/// The blank check for a learned shortcut phrase.
/// This type does not read a clock, a socket, a microphone, or a stored setting.
public enum LearnedPhraseBox {
    /// Space, tab, newline, carriage return, and no-break space. U+200B is not a member.
    /// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so a phrase is not asked of that set.
    public static let blankScalars: Set<Unicode.Scalar> = [
        " ",
        "\t",
        "\n",
        "\r",
        "\u{00A0}",
    ]

    /// Leading and trailing members of `blankScalars` only. A zero-width space stays.
    public static func trimmedPhrase(_ raw: String) -> String {
        let scalars = raw.unicodeScalars
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
}
