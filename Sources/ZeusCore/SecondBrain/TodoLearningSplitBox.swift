import Foundation

/// The blank check for the part trim in `TodoLearning.suggestSplit`.
/// This type does not read a vault, a file, or a clock.
public enum TodoLearningSplitBox {
    /// Space, tab, newline, carriage return, and no-break space. U+200B is not a member.
    /// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so a part is not asked of that set.
    public static let blankScalars: Set<Unicode.Scalar> = [
        " ",
        "\t",
        "\n",
        "\r",
        "\u{00A0}",
    ]

    /// Leading and trailing members of `blankScalars` only. A zero-width space stays.
    public static func trimmedPart(_ raw: String) -> String {
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
