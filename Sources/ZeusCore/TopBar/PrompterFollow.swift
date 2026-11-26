import Foundation

/// Follows a reader through the script word by word from live speech recognition, the way a
/// human prompter operator would: it only moves forward, tolerates mistakes and skipped
/// words, and stays put when you stop talking or ad-lib.
/// Each answer is read from `PrompterFollowBox`.
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
        words = PrompterFollowBox.spokenWords(from: script.blocks.map { block in
            PrompterFollowBox.SpokenBlock(isCue: block.isCue, text: block.text)
        })
    }

    public init(words: [String]) {
        self.words = words
    }

    public static func normalize(_ text: String) -> [String] {
        PrompterFollowBox.normalize(text)
    }

    public var progress: Double { PrompterFollowBox.progress(position: position, count: words.count) }
    public var isFinished: Bool { PrompterFollowBox.isFinished(position: position, count: words.count) }

    public mutating func reset(to position: Int = 0) {
        self.position = PrompterFollowBox.reset(to: position, count: words.count)
    }

    /// Feeds the recognizer's running transcript (partial results grow). Matches its last
    /// few words against the script just ahead of the current position. Returns true if moved.
    @discardableResult
    public mutating func hear(_ transcript: String) -> Bool {
        let step = PrompterFollowBox.hear(
            words: words,
            position: position,
            lookahead: lookahead,
            minimumRun: minimumRun,
            transcript: transcript
        )
        position = step.position
        return step.moved
    }
}

/// Keys the floating teleprompter understands while it is focused.
/// Each answer is read from `PrompterFollowBox`.
public enum PrompterKey: Equatable, Sendable {
    case toggle, stop, faster, slower, previousCue, nextCue, larger, smaller, mirror, restart

    /// macOS virtual key codes and characters → command.
    public static func command(keyCode: UInt16, characters: String?) -> PrompterKey? {
        PrompterFollowBox.command(keyCode: keyCode, characters: characters)
    }
}

/// Turns an imported text or Markdown file into a prompter script: headings stay as cues,
/// formatting and links are dropped, list items become their own paragraphs.
/// Each answer is read from `PrompterFollowBox`.
public enum PrompterImport {
    public static func script(from text: String, isMarkdown: Bool) -> String {
        PrompterFollowBox.importScript(from: text, isMarkdown: isMarkdown)
    }

    /// Drops emphasis markers, inline code ticks, images and keeps link text.
    static func inline(_ text: String) -> String {
        PrompterFollowBox.inline(text)
    }

    public static func isMarkdown(pathExtension: String) -> Bool {
        PrompterFollowBox.isMarkdown(pathExtension: pathExtension)
    }
}

/// Where prompter recordings go: ~/Movies, named like screenshots so they sort by time.
/// Each answer is read from `PrompterFollowBox`. The current time zone is used when the caller
/// omits one, and the file manager answers existence when the caller omits that check.
public enum PrompterRecordingName {
    public static func fileName(at date: Date, timeZone: TimeZone = .current) -> String {
        PrompterFollowBox.fileName(at: date, timeZone: timeZone)
    }

    /// A free URL in `folder`, adding " 2", " 3"… if a file with the name exists.
    public static func url(in folder: URL, at date: Date, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        PrompterFollowBox.recordingURL(folder: folder, at: date, timeZone: .current, exists: exists)
    }
}

/// How the floating prompter scrolls.
/// Each title is read from `PrompterFollowBox`.
public enum PrompterFollowMode: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Follows recognized words.
    case words
    /// Scrolls at the set speed while you are speaking (mic level), holds when you pause.
    case voice
    /// Scrolls at the set speed.
    case steady

    public var id: String { rawValue }

    public var title: String { PrompterFollowBox.modeTitle(self) }
}
