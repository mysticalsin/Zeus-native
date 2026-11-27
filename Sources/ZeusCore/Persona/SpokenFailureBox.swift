import Foundation

/// The blank check for a spoken failure line.
/// This type does not read a file, a network, or a clock.
public enum SpokenFailureBox {
    /// Space, tab, newline, carriage return, and no-break space. U+200B is not a member.
    /// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so a line is not asked of that set.
    public static let blankScalars: Set<Unicode.Scalar> = [
        " ",
        "\t",
        "\n",
        "\r",
        "\u{00A0}",
    ]

    /// Runs of `blankScalars` become one space. Leading and trailing members are removed.
    /// A zero-width space stays, including when it is the whole line.
    public static func folded(_ text: String) -> String {
        var scalars: [Unicode.Scalar] = []
        var pendingBlank = false
        for scalar in text.unicodeScalars {
            if blankScalars.contains(scalar) {
                pendingBlank = true
                continue
            }
            if pendingBlank, !scalars.isEmpty {
                scalars.append(" ")
            }
            pendingBlank = false
            scalars.append(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
