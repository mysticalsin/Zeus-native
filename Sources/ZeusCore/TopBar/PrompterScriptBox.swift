import Foundation

/// The blank check for a prompter script line.
/// This type does not read a screen, a pointer, a clock, or a stored setting.
public enum PrompterScriptBox {
    /// Space, tab, newline, carriage return, and no-break space. U+200B is not a member.
    /// Linux `CharacterSet.whitespaces` and `CharacterSet.whitespacesAndNewlines` treat U+200B as blank, so a line is not asked of those sets.
    public static let blankScalars: Set<Unicode.Scalar> = [
        " ",
        "\t",
        "\n",
        "\r",
        "\u{00A0}",
    ]

    /// Leading and trailing members of `blankScalars` only. A zero-width space stays.
    public static func trimmedText(_ raw: String) -> String {
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
