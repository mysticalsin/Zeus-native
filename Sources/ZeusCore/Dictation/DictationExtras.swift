import Foundation

// MARK: Audio kept with history (reprocess with another engine)

/// 16-bit PCM mono WAV, the format ZEUS keeps next to each dictation (`history/<id>/audio.wav`)
/// so a past dictation can be heard again by another engine.
public enum WAVFile {
    public static func encode(_ samples: [Float], sampleRate: Int = 16_000) -> Data {
        var data = Data()
        let bytes = samples.count * 2
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(bytes))
        data.reserveCapacity(44 + bytes)
        for sample in samples {
            append(Int16(max(-1, min(1, sample)) * Float(Int16.max)))
        }
        return data
    }

    /// Samples of a complete 16-bit mono PCM WAV; malformed or truncated containers fail closed.
    public static func decode(_ data: Data) -> (samples: [Float], sampleRate: Int)? {
        data.withUnsafeBytes { bytes in
            // Offsets below are relative to this buffer, including when Data is a nonzero-index slice.
            guard bytes.count >= 44,
                  bytes[0..<4].elementsEqual("RIFF".utf8),
                  bytes[8..<12].elementsEqual("WAVE".utf8) else { return nil }
            func u16(_ offset: Int) -> Int {
                Int(UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self)))
            }
            func u32(_ offset: Int) -> Int {
                Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
            }
            let declared = u32(4)
            guard declared >= 36, declared <= bytes.count - 8 else { return nil }
            let end = declared + 8
            var offset = 12
            var sampleRate: Int?
            var payload: Range<Int>?
            while offset < end {
                guard end - offset >= 8 else { return nil }
                let id = String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
                let size = u32(offset + 4)
                let body = offset + 8
                // Check each complete chunk before reading any format field or sample.
                guard size <= end - body else { return nil }
                if id == "fmt " {
                    guard sampleRate == nil, size >= 16,
                          u16(body) == 1, u16(body + 2) == 1,
                          u16(body + 12) == 2, u16(body + 14) == 16 else { return nil }
                    let rate = u32(body + 4)
                    guard rate > 0, u32(body + 8) == rate * 2 else { return nil }
                    sampleRate = rate
                } else if id == "data" {
                    guard sampleRate != nil, payload == nil, size % 2 == 0 else { return nil }
                    payload = body..<body + size
                }
                offset = body + size
                if size & 1 == 1 {
                    guard offset < end else { return nil }
                    offset += 1 // RIFF pads odd-sized chunks to an even byte boundary.
                }
            }
            guard offset == end, let sampleRate, let payload else { return nil }
            var samples: [Float] = []
            samples.reserveCapacity(payload.count / 2)
            for position in stride(from: payload.lowerBound, to: payload.upperBound, by: 2) {
                let value = Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: position, as: Int16.self))
                samples.append(max(-1, Float(value) / Float(Int16.max)))
            }
            return (samples, sampleRate)
        }
    }
}

extension DictationStore {
    public func audioURL(for id: String) -> URL {
        root.appendingPathComponent("history", isDirectory: true).appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("audio.wav")
    }

    public func saveAudio(_ samples: [Float], for id: String) throws {
        let url = audioURL(for: id)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try WAVFile.encode(samples).write(to: url, options: .atomic)
    }

    public func audio(for id: String) -> [Float]? {
        guard let data = try? Data(contentsOf: audioURL(for: id)) else { return nil }
        return WAVFile.decode(data)?.samples
    }

    public func hasAudio(for id: String) -> Bool {
        FileManager.default.fileExists(atPath: audioURL(for: id).path)
    }
}

extension DictationRecord {
    /// The same dictation run again: new text and mode or engine, same id, time and app, so it
    /// replaces the old entry in history. `rawResult` changes only when the audio was heard again.
    public func reprocessed(mode: DictationMode, rawResult newRaw: String?, result: String,
                            engine newEngine: String?, processingTime: Int) -> DictationRecord {
        var copy = self
        copy.modeKey = mode.key
        copy.modeName = mode.name
        if let newRaw { copy.rawResult = newRaw }
        copy.result = result
        if let newEngine { copy.engine = newEngine }
        copy.processingTime = processingTime
        return copy
    }
}

// MARK: Vocabulary capture

/// Learns from a correction: compares what ZEUS wrote with what the person fixed it to and
/// proposes replacements ("vibe is" → "Vibe Island") and new words for the vocabulary.
public enum VocabularyCapture {
    public struct Suggestion: Equatable, Sendable {
        public var replacements: [Replacement]
        public var words: [String]

        public init(replacements: [Replacement] = [], words: [String] = []) {
            self.replacements = replacements
            self.words = words
        }

        public var isEmpty: Bool { replacements.isEmpty && words.isEmpty }
    }

    public static func suggest(original: String, corrected: String) -> Suggestion {
        let a = tokens(original), b = tokens(corrected)
        var replacements: [Replacement] = []
        var words: [String] = []
        for change in diff(a, b) {
            let from = change.removed.joined(separator: " ")
            let to = change.added.joined(separator: " ")
            guard !to.isEmpty, from != to else { continue }
            if from.isEmpty || normalize(from) == normalize(to) {
                // Pure insertion or a casing fix: the word itself is what should be known.
                words += change.added.filter { $0.contains(where: \.isLetter) }
            } else {
                replacements.append(Replacement(original: from, with: to))
                if to.contains(where: \.isUppercase) { words.append(to) }
            }
        }
        var seen = Set<String>()
        return Suggestion(replacements: replacements, words: words.filter { seen.insert($0.lowercased()).inserted })
    }

    /// Adds a suggestion to a vocabulary, skipping what it already knows.
    public static func merge(_ suggestion: Suggestion, into vocabulary: Vocabulary) -> Vocabulary {
        var result = vocabulary
        let known = Set(vocabulary.words.map { $0.lowercased() })
        result.words += suggestion.words.filter { !known.contains($0.lowercased()) }
        for rule in suggestion.replacements where !vocabulary.replacements.contains(where: {
            $0.original.lowercased() == rule.original.lowercased()
        }) {
            result.replacements.append(rule)
        }
        return result
    }

    /// Words with surrounding punctuation stripped; punctuation alone is not a word.
    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }

    static func normalize(_ text: String) -> String { text.lowercased() }

    struct Change: Equatable {
        var removed: [String]
        var added: [String]
    }

    /// Runs of changed words between two word lists (longest common subsequence). Case matters,
    /// so a casing fix ("zeus" → "ZEUS") shows up as a change.
    static func diff(_ a: [String], _ b: [String]) -> [Change] {
        let n = a.count, m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var changes: [Change] = []
        var current = Change(removed: [], added: [])
        var i = 0, j = 0
        func flush() {
            if !current.removed.isEmpty || !current.added.isEmpty { changes.append(current) }
            current = Change(removed: [], added: [])
        }
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                flush(); i += 1; j += 1
            } else if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
                current.added.append(b[j]); j += 1
            } else {
                current.removed.append(a[i]); i += 1
            }
        }
        flush()
        return changes
    }
}

// MARK: Deep links

/// `zeus://` links, so Shortcuts, Raycast, Stream Deck or a script can drive ZEUS:
/// `zeus://dictation/start`, `/stop`, `/toggle`, `/cancel`, `zeus://dictation/mode?key=email`,
/// `zeus://chat/open?text=…`, `zeus://chat/new`.
public enum ZeusDeepLink: Equatable, Sendable {
    case dictationStart
    case dictationStop
    case dictationToggle
    case dictationCancel
    case dictationMode(String)
    case chatOpen(prefill: String?)
    case chatNew
    /// `zeus://prompter`: show or hide the floating teleprompter.
    case prompter
    /// `zeus://sticky/new?text=…`: a new sticky note.
    case stickyNew(text: String?)

    public static let scheme = "zeus"

    public static func parse(_ url: URL) -> ZeusDeepLink? {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        // zeus://dictation/start → host "dictation", path "/start"; zeus:dictation/start has no host.
        var parts = components.path.split(separator: "/").map { $0.lowercased() }
        if let host = components.host?.lowercased(), !host.isEmpty { parts.insert(host, at: 0) }
        let query = Dictionary((components.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        switch (parts.first, parts.dropFirst().first) {
        case ("dictation", "start"), ("dictate", nil): return .dictationStart
        case ("dictation", "stop"): return .dictationStop
        case ("dictation", "toggle"): return .dictationToggle
        case ("dictation", "cancel"): return .dictationCancel
        case ("dictation", "mode"):
            let key = query["key"] ?? parts.dropFirst(2).first ?? ""
            return key.isEmpty ? nil : .dictationMode(key)
        case ("chat", "new"): return .chatNew
        case ("prompter", _), ("teleprompter", _): return .prompter
        case ("sticky", nil), ("sticky", "new"), ("note", "new"):
            let text = query["text"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .stickyNew(text: text?.isEmpty == false ? text : nil)
        case ("chat", "open"), ("chat", nil):
            let text = query["text"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .chatOpen(prefill: text?.isEmpty == false ? text : nil)
        default: return nil
        }
    }
}

// MARK: Typing instead of pasting

/// Splits text for synthetic key events: each event carries at most `limit` UTF-16 units
/// (macOS ignores more), never splitting a character, and newlines become their own Return press.
public enum KeystrokeTyping {
    public enum Piece: Equatable, Sendable {
        case text(String)
        case newline
    }

    public static func pieces(_ text: String, limit: Int = 20) -> [Piece] {
        var result: [Piece] = []
        var chunk = ""
        func flush() {
            if !chunk.isEmpty { result.append(.text(chunk)) }
            chunk = ""
        }
        for character in text {
            if character.isNewline {
                flush()
                result.append(.newline)
                continue
            }
            if chunk.utf16.count + String(character).utf16.count > limit { flush() }
            chunk.append(character)
        }
        flush()
        return result
    }

    /// Apps where ⌘V is ignored or blocked (remote desktops, VMs, some terminals). People can add more.
    public static let defaultBundleIDs: [String] = [
        "com.microsoft.rdc.macos",
        "com.parallels.desktop.console",
        "com.vmware.fusion",
        "com.citrix.receiver.icaviewer.mac",
        "com.realvnc.vncviewer",
    ]

    public static func shouldType(bundleID: String?, alwaysType: Bool, typedApps: [String]) -> Bool {
        if alwaysType { return true }
        guard let bundleID else { return false }
        return typedApps.contains(bundleID)
    }
}

// MARK: Microphone

/// An audio input on this Mac.
public struct MicrophoneDevice: Codable, Equatable, Identifiable, Sendable {
    public var uid: String
    public var name: String
    public var isDefault: Bool

    public var id: String { uid }

    public init(uid: String, name: String, isDefault: Bool = false) {
        self.uid = uid
        self.name = name
        self.isDefault = isDefault
    }

    /// The saved choice if it is still plugged in, else the system default (nil = follow system).
    public static func resolve(savedUID: String?, devices: [MicrophoneDevice]) -> MicrophoneDevice? {
        if let savedUID, let match = devices.first(where: { $0.uid == savedUID }) { return match }
        return devices.first(where: \.isDefault) ?? devices.first
    }
}

/// Microphone level as the notch and the mic test show it.
public enum MicLevel {
    /// RMS of a buffer mapped to 0…1 with a small noise floor, the curve the notch bars use.
    public static func level(samples: UnsafeBufferPointer<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        let rms = sqrt(sum / Float(samples.count))
        return Double(min(max((rms - 0.008) * 10.2, 0), 1))
    }

    public static func level(_ samples: [Float]) -> Double {
        samples.withUnsafeBufferPointer { level(samples: $0) }
    }

    /// Words for the mic test: too quiet, good, too loud (clipping).
    public static func verdict(peak: Double) -> String {
        switch peak {
        case ..<0.08: "Too quiet. Move closer or pick another microphone."
        case ..<0.95: "Sounds good."
        default: "Very loud. Move back a little."
        }
    }
}
