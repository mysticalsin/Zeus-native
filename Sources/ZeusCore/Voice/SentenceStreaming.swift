import Foundation

/// How a reply reaches the speaker while the model is still writing it. The brain feeds sentences
/// as soon as each one is complete (`SentenceChunker`); playback starts on the first sentence.
/// Documented in docs/VOICE-PIPELINE.md.
public struct SpeakOutcome: Equatable, Sendable {
    public var engine: String
    public var voice: String
    public var reason: String
    /// From the call to the first buffer scheduled for playback. Nil when nothing played.
    public var firstAudioMs: Int?
    public var sentences: Int

    public init(engine: String, voice: String, reason: String, firstAudioMs: Int?, sentences: Int) {
        self.engine = engine
        self.voice = voice
        self.reason = reason
        self.firstAudioMs = firstAudioMs
        self.sentences = sentences
    }
}

@MainActor
public protocol SentenceSpeaking: AnyObject {
    /// Speaks each sentence as it arrives, in order, and returns when the last one has played or
    /// the task is cancelled. Engines synthesize the next sentence while the previous one plays.
    func speak(sentenceStream: AsyncStream<String>) async -> SpeakOutcome
    /// Warms the chosen engine. Called on the first talk-key press, never at launch.
    func prewarm()
    func stop()
}

/// Splits streamed text deltas into complete sentences. A sentence ends at . ! ? followed by a space or
/// the end of the stream; decimals ("3.5") and common abbreviations do not end one.
public struct SentenceChunker: Sendable {
    private var buffer = ""
    private static let abbreviations: Set<String> = ["mr", "mrs", "ms", "dr", "st", "vs", "etc", "e.g", "i.e"]

    public init() {}

    public mutating func feed(_ delta: String) -> [String] {
        buffer += delta
        var out: [String] = []
        let chars = Array(buffer)
        var start = 0
        var index = 0
        while index < chars.count {
            let c = chars[index]
            if ".!?".contains(c), index + 1 < chars.count, chars[index + 1].isWhitespace || chars[index + 1] == "\n" {
                let sentence = String(chars[start...index]).trimmingCharacters(in: .whitespacesAndNewlines)
                let lastWord = sentence.dropLast().split(separator: " ").last.map { $0.lowercased() } ?? ""
                if !Self.abbreviations.contains(lastWord), sentence.count > 1 {
                    out.append(sentence)
                    start = index + 1
                }
            }
            index += 1
        }
        let rest = String(chars[start...])
        buffer = rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : rest
        return out
    }

    /// The trailing text when the stream ends.
    public mutating func flush() -> String? {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest.isEmpty ? nil : rest
    }
}

/// One line per engine tried by the owner's voice self-test.
public struct VoiceSelfTestRow: Codable, Equatable, Sendable {
    public var engine: String
    public var available: Bool
    public var reason: String
    public var spoke: Bool
    public var firstAudioMs: Int?
    public var effectPercent: Int

    public init(engine: String, available: Bool, reason: String, spoke: Bool, firstAudioMs: Int?, effectPercent: Int) {
        self.engine = engine
        self.available = available
        self.reason = reason
        self.spoke = spoke
        self.firstAudioMs = firstAudioMs
        self.effectPercent = effectPercent
    }
}

public struct VoiceSelfTestReceipt: Codable, Equatable, Sendable {
    public var created: String
    public var line: String
    public var systemVoice: String
    public var rows: [VoiceSelfTestRow]

    public init(created: String, line: String, systemVoice: String, rows: [VoiceSelfTestRow]) {
        self.created = created
        self.line = line
        self.systemVoice = systemVoice
        self.rows = rows
    }

    /// The test passes when the system fallback spoke through the effect and no row used Samantha.
    public var passed: Bool {
        rows.contains { $0.engine == UltronEngine.system.logName && $0.spoke }
            && !systemVoice.lowercased().contains("samantha")
    }

    public func json() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}
