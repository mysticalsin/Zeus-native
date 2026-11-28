import Foundation

/// The blank check for the highlight trim in `ZeusTagParser.parseHighlight`.
/// This type does not read a vault, a file, or a clock.
public enum HighlightTrimBox {
    /// Space, tab, newline, carriage return, and no-break space. U+200B is not a member.
    /// Linux `CharacterSet.whitespaces` treats U+200B as blank, so a highlight inner is not asked of that set.
    public static let blankScalars: Set<Unicode.Scalar> = [
        " ",
        "\t",
        "\n",
        "\r",
        "\u{00A0}",
    ]

    /// Leading and trailing members of `blankScalars` only. A zero-width space stays.
    public static func trimmedHighlight(_ raw: String) -> String {
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
