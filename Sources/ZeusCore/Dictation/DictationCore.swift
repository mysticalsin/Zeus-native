import Foundation

/// A deterministic fix applied after speech recognition ("zeus dot app" → "zeus.app").
public struct Replacement: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var original: String
    public var with: String

    public init(id: UUID = UUID(), original: String, with: String) {
        self.id = id
        self.original = original
        self.with = with
    }
}

/// Words the recognizer should expect (names, jargon) and fixes to apply afterwards.
public struct Vocabulary: Codable, Equatable, Sendable {
    public var words: [String]
    public var replacements: [Replacement]

    public init(words: [String] = [], replacements: [Replacement] = []) {
        self.words = words
        self.replacements = replacements
    }

    /// Hints for the recognizer: trimmed, unique, capped so a long list can't degrade results.
    public var hints: [String] {
        var seen = Set<String>()
        return words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(100)
            .map { $0 }
    }

    /// Case-insensitive, whole-word replacements, longest phrase first so "super whisper app"
    /// wins over "super whisper". Vocabulary words are also restored to their exact casing.
    public func apply(to text: String) -> String {
        var result = text
        let ordered = replacements
            .filter { !$0.original.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.original.count > $1.original.count }
        for rule in ordered {
            result = Self.replaceWholeWord(rule.original, with: rule.with, in: result)
        }
        for word in hints where word.contains(where: \.isUppercase) {
            result = Self.replaceWholeWord(word, with: word, in: result)
        }
        return result
    }

    static func replaceWholeWord(_ target: String, with replacement: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: target.trimmingCharacters(in: .whitespaces))
        let pattern = "(?<![\\p{L}\\p{N}])" + escaped + "(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let template = NSRegularExpression.escapedTemplate(for: replacement)
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// One word per line; "a -> b" lines become replacements. Used by the Settings editor.
    public static func parse(_ text: String) -> Vocabulary {
        var vocabulary = Vocabulary()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if let arrow = line.range(of: "->") {
                let from = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
                let to = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
                if !from.isEmpty { vocabulary.replacements.append(Replacement(original: from, with: to)) }
            } else {
                vocabulary.words.append(line)
            }
        }
        return vocabulary
    }

    public var editableText: String {
        (words + replacements.map { "\($0.original) -> \($0.with)" }).joined(separator: "\n")
    }
}

/// What happens to a dictation after it is transcribed.
public struct DictationMode: Codable, Equatable, Identifiable, Sendable {
    public struct Example: Codable, Equatable, Sendable {
        public var input: String
        public var output: String
        public init(input: String, output: String) {
            self.input = input
            self.output = output
        }
    }

    public var key: String
    public var name: String
    public var symbol: String
    /// Empty prompt means plain voice to text: no AI pass, nothing leaves the Mac.
    public var prompt: String
    public var examples: [Example]
    /// Bundle IDs that switch to this mode automatically while frontmost.
    public var activationApps: [String]
    public var useSelectedText: Bool
    public var useClipboard: Bool
    /// Press Return after pasting (chat boxes).
    public var autoSend: Bool

    public var id: String { key }
    public var usesAI: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public init(key: String, name: String, symbol: String = "waveform", prompt: String = "", examples: [Example] = [],
                activationApps: [String] = [], useSelectedText: Bool = false, useClipboard: Bool = false, autoSend: Bool = false) {
        self.key = key
        self.name = name
        self.symbol = symbol
        self.prompt = prompt
        self.examples = examples
        self.activationApps = activationApps
        self.useSelectedText = useSelectedText
        self.useClipboard = useClipboard
        self.autoSend = autoSend
    }

    /// ZEUS's own starting set. The prompts are written for ZEUS, short and editable.
    public static let builtIns: [DictationMode] = [
        DictationMode(key: "voice", name: "Voice", symbol: "waveform"),
        DictationMode(
            key: "message", name: "Message", symbol: "bubble.left.fill",
            prompt: "Clean up this spoken message for a chat app. Fix punctuation and obvious speech slips, drop filler words, keep the speaker's tone and language. Keep it short. Return only the message.",
            activationApps: ["com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "net.whatsapp.WhatsApp", "com.hnc.Discord", "ru.keepcoder.Telegram"]
        ),
        DictationMode(
            key: "email", name: "Email", symbol: "envelope.fill",
            prompt: "Turn this dictation into a clear email body. Add a greeting and sign-off only if the speaker implied them. Use short paragraphs, keep every fact, keep the speaker's language. Return only the email text.",
            activationApps: ["com.apple.mail", "com.microsoft.Outlook", "com.superhuman.electron"]
        ),
        DictationMode(
            key: "note", name: "Note", symbol: "note.text",
            prompt: "Turn this dictation into a tidy note: a one-line title, then bullet points. Keep every fact and name, remove filler, keep the speaker's language. Return only the note in Markdown.",
            activationApps: ["md.obsidian", "com.apple.Notes", "notion.id"]
        ),
        DictationMode(
            key: "prompt", name: "Agent prompt", symbol: "terminal.fill",
            prompt: "Rewrite this dictation as a precise instruction for a coding agent. Keep file names, commands and identifiers exact, use a short numbered list if there are several steps. Return only the instruction.",
            activationApps: ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "com.todesktop.230313mzl4w4u92", "dev.warp.Warp-Stable"],
            useSelectedText: true
        ),
    ]

    /// The mode for the app in front: a mode that lists the app wins, otherwise the chosen one.
    public static func resolve(_ modes: [DictationMode], selectedKey: String, frontmostBundleID: String?, autoSwitch: Bool) -> DictationMode {
        if autoSwitch, let bundle = frontmostBundleID,
           let match = modes.first(where: { $0.activationApps.contains(bundle) }) {
            return match
        }
        return modes.first { $0.key == selectedKey } ?? modes.first ?? builtIns[0]
    }

    /// The text sent to the language model for an AI mode.
    public func buildPrompt(transcript: String, selectedText: String?, clipboard: String?, appName: String?) -> String {
        var parts = ["# Instructions", prompt]
        if !examples.isEmpty {
            parts.append("# Examples")
            for example in examples {
                parts.append("Input: \(example.input)\nOutput: \(example.output)")
            }
        }
        if let appName, !appName.isEmpty { parts.append("# Active app\n\(appName)") }
        if useSelectedText, let selectedText, !selectedText.isEmpty { parts.append("# Selected text\n\(selectedText)") }
        if useClipboard, let clipboard, !clipboard.isEmpty { parts.append("# Clipboard\n\(clipboard)") }
        parts.append("# Dictation\n\(transcript)")
        return parts.joined(separator: "\n\n")
    }
}

/// One finished dictation, kept on this Mac only. Field names follow the common
/// `meta.json` shape used by dictation tools so existing scripts can read the folder.
public struct DictationRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var datetime: Date
    /// Milliseconds of audio.
    public var duration: Int
    /// Milliseconds from release to text.
    public var processingTime: Int
    public var modeKey: String
    public var modeName: String
    public var rawResult: String
    public var result: String
    public var appBundleID: String?
    public var appName: String?
    public var inserted: Bool
    public var source: String
    /// Which speech engine heard it (`TranscriptionEngineKind` raw value); nil in older records.
    public var engine: String?

    public init(id: String = UUID().uuidString, datetime: Date = Date(), duration: Int, processingTime: Int,
                modeKey: String, modeName: String, rawResult: String, result: String,
                appBundleID: String? = nil, appName: String? = nil, inserted: Bool = false, source: String = "microphone",
                engine: String? = nil) {
        self.id = id
        self.datetime = datetime
        self.duration = duration
        self.processingTime = processingTime
        self.modeKey = modeKey
        self.modeName = modeName
        self.rawResult = rawResult
        self.result = result
        self.appBundleID = appBundleID
        self.appName = appName
        self.inserted = inserted
        self.source = source
        self.engine = engine
    }

    public var wordCount: Int { result.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count }
}

/// What a history read found: the readable records and the metadata files that were not.
public struct DictationHistoryLoad: Sendable {
    public var records: [DictationRecord]
    /// Backup (or, if the move failed, original) locations of unreadable `meta.json` files.
    public var problems: [URL]

    public var isClean: Bool { problems.isEmpty }
}

/// Dictation history, modes and vocabulary as plain JSON under one folder:
/// `history/<id>/meta.json`, `modes/<key>.json`, `vocabulary.json`.
public struct DictationStore: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    private var historyDir: URL { root.appendingPathComponent("history", isDirectory: true) }
    private var modesDir: URL { root.appendingPathComponent("modes", isDirectory: true) }
    private var vocabularyURL: URL { root.appendingPathComponent("vocabulary.json") }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func save(_ record: DictationRecord) throws {
        let folder = historyDir.appendingPathComponent(record.id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.encoder().encode(record).write(to: folder.appendingPathComponent("meta.json"), options: .atomic)
    }

    /// Newest first. A corrupt metadata file is set aside (see `loadHistory`).
    public func history(limit: Int = 200) -> [DictationRecord] {
        loadHistory(limit: limit).records
    }

    /// Newest first, plus any metadata file that could not be read. An unreadable `meta.json` is moved
    /// aside to `meta.json.<timestamp>.corrupt` (0600) so it is never overwritten, and listed in
    /// `problems`. Folders with no `meta.json` are not an error.
    public func loadHistory(limit: Int = 200, now: Date = Date()) -> DictationHistoryLoad {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: historyDir, includingPropertiesForKeys: nil)) ?? []
        var records: [DictationRecord] = []
        var problems: [URL] = []
        for folder in folders {
            let meta = folder.appendingPathComponent("meta.json")
            guard fm.fileExists(atPath: meta.path) else { continue }
            if let data = try? Data(contentsOf: meta), let record = try? Self.decoder().decode(DictationRecord.self, from: data) {
                records.append(record)
            } else {
                problems.append(Self.quarantine(meta, now: now))
            }
        }
        return DictationHistoryLoad(records: Array(records.sorted { $0.datetime > $1.datetime }.prefix(limit)), problems: problems)
    }

    /// Moves a bad file next to itself as a `.corrupt` backup. Returns the backup, or the original
    /// location when the move failed (the file is then left untouched).
    private static func quarantine(_ file: URL, now: Date) -> URL {
        let fm = FileManager.default
        let stamp = Int(now.timeIntervalSince1970)
        var backup = file.deletingLastPathComponent().appendingPathComponent("\(file.lastPathComponent).\(stamp).corrupt")
        var counter = 1
        while fm.fileExists(atPath: backup.path) {
            backup = file.deletingLastPathComponent().appendingPathComponent("\(file.lastPathComponent).\(stamp)-\(counter).corrupt")
            counter += 1
        }
        do {
            try fm.moveItem(at: file, to: backup)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            return backup
        } catch {
            return file
        }
    }

    public func delete(_ id: String) {
        try? FileManager.default.removeItem(at: historyDir.appendingPathComponent(id, isDirectory: true))
    }

    /// Removes records older than `days` (0 keeps everything). Returns how many went. Nothing is
    /// removed when the history had an unreadable file: a failed load never drives deletion.
    @discardableResult
    public func prune(olderThanDays days: Int, now: Date = Date()) -> Int {
        guard days > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let load = loadHistory(limit: .max, now: now)
        guard load.isClean else { return 0 }
        let old = load.records.filter { $0.datetime < cutoff }
        old.forEach { delete($0.id) }
        return old.count
    }

    /// Built-ins, overridden or extended by any JSON files in `modes/`.
    public func modes() -> [DictationMode] {
        var modes = DictationMode.builtIns
        let files = (try? FileManager.default.contentsOfDirectory(at: modesDir, includingPropertiesForKeys: nil)) ?? []
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: file), let mode = try? Self.decoder().decode(DictationMode.self, from: data) else { continue }
            if let index = modes.firstIndex(where: { $0.key == mode.key }) { modes[index] = mode } else { modes.append(mode) }
        }
        return modes
    }

    public func save(_ mode: DictationMode) throws {
        try FileManager.default.createDirectory(at: modesDir, withIntermediateDirectories: true)
        try Self.encoder().encode(mode).write(to: modesDir.appendingPathComponent("\(mode.key).json"), options: .atomic)
    }

    public func vocabulary() -> Vocabulary {
        guard let data = try? Data(contentsOf: vocabularyURL) else { return Vocabulary() }
        return (try? Self.decoder().decode(Vocabulary.self, from: data)) ?? Vocabulary()
    }

    public func save(_ vocabulary: Vocabulary) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.encoder().encode(vocabulary).write(to: vocabularyURL, options: .atomic)
    }
}
