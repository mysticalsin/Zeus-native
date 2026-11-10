import Foundation

/// Follows a reader through the script word by word from live speech recognition, the way a
/// human prompter operator would: it only moves forward, tolerates mistakes and skipped
/// words, and stays put when you stop talking or ad-lib.
public struct ScriptFollower: Equatable, Sendable {
    /// Script words, normalized (lowercased, no punctuation), cues left out.
    public let words: [String]
    /// Index of the next word to be read.
    public private(set) var position: Int = 0
    /// How far ahead a match may jump (words), so a common word late in the script can't
    /// steal the position.
    public var lookahead: Int = 40
    /// Spoken words that must match in a row before the position moves.
    public var minimumRun: Int = 2

    public init(script: PrompterScript) {
        words = script.blocks.filter { !$0.isCue }.flatMap { Self.normalize($0.text) }
    }

    public init(words: [String]) {
        self.words = words
    }

    public static func normalize(_ text: String) -> [String] {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" }
            .map { $0.replacingOccurrences(of: "'", with: "") }
            .filter { !$0.isEmpty }
    }

    public var progress: Double { words.isEmpty ? 0 : Double(position) / Double(words.count) }
    public var isFinished: Bool { position >= words.count }

    public mutating func reset(to position: Int = 0) {
        self.position = min(max(position, 0), words.count)
    }

    /// Feeds the recognizer's running transcript (partial results grow). Matches its last
    /// few words against the script just ahead of the current position. Returns true if moved.
    @discardableResult
    public mutating func hear(_ transcript: String) -> Bool {
        let spoken = Self.normalize(transcript).suffix(8)
        guard spoken.count >= minimumRun, position < words.count else { return false }
        let tail = Array(spoken)
        var best: (end: Int, run: Int)?
        let start = max(0, position - 3)
        let end = min(words.count, position + lookahead)
        guard start < end else { return false }
        for index in start..<end {
            // Longest run of spoken words that ends at script word `index`.
            var run = 0
            while run < tail.count, index - run >= 0, words[index - run] == tail[tail.count - 1 - run] {
                run += 1
            }
            guard run >= minimumRun else { continue }
            // Prefer longer runs, then the nearest one.
            if best == nil || run > best!.run { best = (index, run) }
        }
        guard let best, best.end + 1 > position else { return false }
        position = best.end + 1
        return true
    }
}

/// Keys the floating teleprompter understands while it is focused.
public enum PrompterKey: Equatable, Sendable {
    case toggle, stop, faster, slower, previousCue, nextCue, larger, smaller, mirror, restart

    /// macOS virtual key codes and characters → command.
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
}

/// Turns an imported text or Markdown file into a prompter script: headings stay as cues,
/// formatting and links are dropped, list items become their own paragraphs.
public enum PrompterImport {
    public static func script(from text: String, isMarkdown: Bool) -> String {
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
                lines.append("")  // each item reads as its own paragraph
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

    /// Drops emphasis markers, inline code ticks, images and keeps link text.
    static func inline(_ text: String) -> String {
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
}

/// Where prompter recordings go: ~/Movies, named like screenshots so they sort by time.
public enum PrompterRecordingName {
    public static func fileName(at date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "ZEUS Prompter \(formatter.string(from: date)).mov"
    }

    /// A free URL in `folder`, adding " 2", " 3"… if a file with the name exists.
    public static func url(in folder: URL, at date: Date, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let base = fileName(at: date)
        var candidate = folder.appendingPathComponent(base)
        var counter = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent(base.replacingOccurrences(of: ".mov", with: " \(counter).mov"))
            counter += 1
        }
        return candidate
    }
}

/// How the floating prompter scrolls.
public enum PrompterFollowMode: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Follows recognized words.
    case words
    /// Scrolls at the set speed while you are speaking (mic level), holds when you pause.
    case voice
    /// Scrolls at the set speed.
    case steady

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .words: "Follow my words"
        case .voice: "Scroll while I speak"
        case .steady: "Steady speed"
        }
    }
}
