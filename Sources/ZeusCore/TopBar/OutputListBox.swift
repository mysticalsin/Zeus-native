import Foundation

/// The name kept when sound leaves for another output.
/// This type does not read a screen, a pointer, a clock, or a stored setting, and it does not open a device.
public enum OutputListBox {
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

    /// An empty name is not a blank. A name of only named blanks is a blank.
    /// A name that also holds U+200B is not a blank.
    public static func isBlank(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { blankScalars.contains($0) }
    }

    /// Leading and trailing members of `blankScalars` only. A zero-width space stays.
    public static func trimmed(_ name: String) -> String {
        let scalars = name.unicodeScalars
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

    /// Nil when missing or only named blanks. A zero-width space is a name.
    public static func usable(_ name: String?) -> String? {
        guard let name else { return nil }
        let text = trimmed(name)
        return text.isEmpty ? nil : text
    }
}
