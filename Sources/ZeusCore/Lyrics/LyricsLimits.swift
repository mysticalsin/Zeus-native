import Foundation

/// The size bounds for lyric data, which comes from the network and from a player's tags. Every scan and every
/// draw works on input cut to these sizes, so a hostile body or title costs a fixed amount of work.
public enum LyricsLimits {
    /// The most bytes of one reply Zeus reads. A bigger reply counts as a failed request and is never cached.
    public static let maxReplyBytes = 512 * 1024
    /// The most bytes one cached answer may take on disk; a bigger answer is shown but not kept.
    public static let maxCachedEntryBytes = 512 * 1024
    /// The most timed lines one lyric keeps.
    public static let maxLines = 2_000
    /// The most characters one lyric line keeps. The row shows two lines of text, far less than this.
    public static let maxLineCharacters = 300
    /// A line longer than this is shown whole instead of being lit word by word.
    public static let maxWordLitCharacters = 200
    /// The shortest sleep between two word changes of the lit line: at most 20 redraws a second.
    public static let minimumWordWake: TimeInterval = 0.05
    /// A title longer than this is never cleaned up: no real release suffix sits in a title that long.
    public static let maxTitleCharacters = 500
    /// A word tag (`<mm:ss.xx>`) is never longer than this; a longer `<...>` stays as text.
    public static let maxWordTagCharacters = 16

    /// `text` cut to `maxLineCharacters`, with the blanks the cut leaves at either end removed.
    /// A zero-width space stays. The blank check is read from `LyricsLimitsBox`.
    public static func clipped(_ text: String) -> String {
        guard text.count > maxLineCharacters else { return text }
        return LyricsLimitsBox.trimmedLine(String(text.prefix(maxLineCharacters)))
    }

    /// `lines` cut to `maxLines`, each line cut to `maxLineCharacters`. The same array when nothing is over a limit.
    public static func clamped(_ lines: [LyricLine]) -> [LyricLine] {
        let overLong = lines.contains { $0.text.count > maxLineCharacters }
        guard lines.count > maxLines || overLong else { return lines }
        return lines.prefix(maxLines).map { LyricLine(time: $0.time, text: clipped($0.text)) }
    }

    /// Whether a line is short enough to be lit word by word.
    public static func lightsWords(in text: String) -> Bool { text.count <= maxWordLitCharacters }
}
