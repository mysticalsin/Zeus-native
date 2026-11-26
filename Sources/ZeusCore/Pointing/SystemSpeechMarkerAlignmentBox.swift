import Foundation

/// Whether one system-speech token is a blank.
/// This type does not call a synthesizer and does not read a clock.
public enum SystemSpeechMarkerAlignmentBox {
    /// Spaces and line breaks, named as scalars. U+200B is not a member. Linux
    /// `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so a word is not asked of that set.
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

    /// True when every scalar is in `blankScalars`. An empty token is not a blank.
    /// A zero-width space is not a blank, even beside named blanks.
    public static func isBlank(_ token: String) -> Bool {
        let scalars = token.unicodeScalars
        return !scalars.isEmpty && scalars.allSatisfy { blankScalars.contains($0) }
    }
}
