import Foundation

/// Whether an earbud cue may take the notch, and for how long.
/// This type does not read a screen, a pointer, a clock, or a stored setting.
public enum EarbudsCuePolicyBox {
    /// Spaces and line breaks, named as scalars. U+200B is not a member. Linux
    /// `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so an id is not asked of that set.
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

    public static let connectedDuration: TimeInterval = 4
    public static let disconnectedDuration: TimeInterval = 3

    /// Leading and trailing members of `blankScalars` only. A zero-width space stays.
    public static func trimmedID(_ id: String) -> String {
        let scalars = id.unicodeScalars
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

    public static func duration(_ kind: EarbudsCueShow.Kind) -> TimeInterval {
        switch kind {
        case .connected, .levels: connectedDuration
        case .disconnected: disconnectedDuration
        }
    }

    /// A blank id is refused. A levels update stays on the connected cue of the same id.
    /// A connect or a disconnect may replace an ordinary cue. A protected cue is never covered.
    public static func mayShow(_ cue: EarbudsCueShow, over current: EarbudsCueOccupant) -> Bool {
        let id = trimmedID(cue.id)
        guard !id.isEmpty else { return false }
        if case .protected = current { return false }
        switch cue.kind {
        case .levels:
            guard case .earbuds(let currentID, _, true) = current else { return false }
            return trimmedID(currentID) == id
        case .connected, .disconnected:
            return true
        }
    }
}
