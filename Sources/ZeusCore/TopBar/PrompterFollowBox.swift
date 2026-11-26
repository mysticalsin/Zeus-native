import Foundation

/// Word following, key commands, Markdown import, recording names, and follow-mode titles.
/// A run shorter than the minimum does not move. The spoken tail is the last eight words.
/// Equal runs keep the earlier match. A match that does not end past the current word stays put.
/// A blank cue title is dropped. A pace is not read here.
/// This type does not read a screen, a pointer, a clock, or a stored setting, and it does not touch the file system.
/// The caller passes the date, the time zone, and whether a recording URL already exists.
public enum PrompterFollowBox {
    /// One display block. A cue is a section title and is not spoken.
    public struct SpokenBlock: Equatable, Sendable {
        public var isCue: Bool
        public var text: String

        public init(isCue: Bool, text: String) {
            self.isCue = isCue
            self.text = text
        }
    }

    /// Where the follower sits after one transcript.
    public struct HearStep: Equatable, Sendable {
        public var position: Int
        public var moved: Bool

        public init(position: Int, moved: Bool) {
            self.position = position
            self.moved = moved
        }
    }

    /// Lowercased words with marks folded. Apostrophes are removed. Other punctuation splits words.
    public static func normalize(_ text: String) -> [String] {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" }
            .map { $0.replacingOccurrences(of: "'", with: "") }
            .filter { !$0.isEmpty }
    }

    /// Spoken words, cue titles left out.
    public static func spokenWords(from blocks: [SpokenBlock]) -> [String] {
        blocks.filter { !$0.isCue }.flatMap { normalize($0.text) }
    }

    /// 0 at the start and 1 when every word has been read. An empty script is 0.
    public static func progress(position: Int, count: Int) -> Double {
        count == 0 ? 0 : Double(position) / Double(count)
    }

    /// True once the position has reached the last word, including an empty script.
    public static func isFinished(position: Int, count: Int) -> Bool {
        position >= count
    }

    /// A negative position sits at the start. A position past the end sits on the last word.
    public static func reset(to position: Int, count: Int) -> Int {
        min(max(position, 0), count)
    }

    /// Matches the last words of `transcript` against the script just ahead of `position`.
    /// The tail is at most eight words. A run shorter than `minimumRun` does not move.
    /// The window starts three words behind `position` and extends `lookahead` words ahead.
    /// A longer run wins. Equal runs keep the earlier index. The position never moves backward.
    public static func hear(words: [String], position: Int, lookahead: Int, minimumRun: Int, transcript: String) -> HearStep {
        let spoken = normalize(transcript).suffix(8)
        guard spoken.count >= minimumRun, position < words.count else {
            return HearStep(position: position, moved: false)
        }
        let tail = Array(spoken)
        var best: (end: Int, run: Int)?
        let start = max(0, position - 3)
        let end = min(words.count, position + lookahead)
        guard start < end else { return HearStep(position: position, moved: false) }
        for index in start..<end {
            var run = 0
            while run < tail.count, index - run >= 0, words[index - run] == tail[tail.count - 1 - run] {
                run += 1
            }
            guard run >= minimumRun else { continue }
            if best == nil || run > best!.run { best = (index, run) }
        }
        guard let best, best.end + 1 > position else { return HearStep(position: position, moved: false) }
        return HearStep(position: best.end + 1, moved: true)
    }

    /// macOS virtual key codes and characters. A known key code wins over the character.
    public static func command(keyCode: UInt16, characters: String?) -> PrompterKey? {
        switch keyCode {
        case 49: return .toggle      // Space
        case 53: return .stop        // Escape
        case 126: return .faster     // Up arrow
        case 125: return .slower     // Down arrow
        case 123: return .previousCue
        case 124: return .nextCue
        default: break
        }
        switch characters?.lowercased() {
        case "+", "=": return .larger
        case "-", "_": return .smaller
        case "m": return .mirror
        case "r": return .restart
        default: return nil
        }
    }

    /// Headings stay as cues. Formatting and links are dropped. List items become their own paragraphs.
    /// A plain file only turns Windows newlines into Unix newlines.
    public static func importScript(from text: String, isMarkdown: Bool) -> String {
        guard isMarkdown else { return text.replacingOccurrences(of: "\r\n", with: "\n") }
        var lines: [String] = []
        var inCode = false
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inCode.toggle(); continue }
            if inCode { continue }
            if trimmed.hasPrefix("#") {
                let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                lines.append(title.isEmpty ? "" : "# " + inline(title))
                continue
            }
            if trimmed.hasPrefix("---") || trimmed.hasPrefix("***") || trimmed.hasPrefix("<!--") { lines.append(""); continue }
            var line = trimmed
            if line.hasPrefix(">") { line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces) }
            if let marker = line.first, "-*+".contains(marker), line.dropFirst().first == " " {
                line = String(line.dropFirst(2))
                lines.append("")
            } else if let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }),
                      line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                      line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " " {
                line = String(line[line.index(dot, offsetBy: 2)...])
                lines.append("")
            }
            lines.append(inline(line))
        }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops emphasis markers, inline code ticks, and images, and keeps link text.
    public static func inline(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^)]*\\)", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        for marker in ["**", "__", "`", "~~"] { result = result.replacingOccurrences(of: marker, with: "") }
        result = result.replacingOccurrences(of: "(?<![\\p{L}\\p{N}])[*_]([^*_]+)[*_](?![\\p{L}\\p{N}])", with: "$1", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }

    public static func isMarkdown(pathExtension: String) -> Bool {
        ["md", "markdown", "mdown", "mkd"].contains(pathExtension.lowercased())
    }

    /// `yyyy-MM-dd at HH.mm.ss` in `timeZone`, with a POSIX locale so the name does not follow the region.
    public static func fileName(at date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "ZEUS Prompter \(formatter.string(from: date)).mov"
    }

    /// A free URL in `folder`. The second file is ` 2`, then ` 3`, and so on.
    public static func recordingURL(folder: URL, at date: Date, timeZone: TimeZone, exists: (URL) -> Bool) -> URL {
        let base = fileName(at: date, timeZone: timeZone)
        var candidate = folder.appendingPathComponent(base)
        var counter = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent(base.replacingOccurrences(of: ".mov", with: " \(counter).mov"))
            counter += 1
        }
        return candidate
    }

    public static func modeTitle(_ mode: PrompterFollowMode) -> String {
        switch mode {
        case .words: "Follow my words"
        case .voice: "Scroll while I speak"
        case .steady: "Steady speed"
        }
    }
}
