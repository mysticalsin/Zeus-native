import Foundation

/// Languages exposed by the local dictation controls. Automatic follows the Mac's
/// preferred language for Apple Speech and lets multilingual local engines detect it.
public enum DictationLanguage: String, CaseIterable, Hashable, Identifiable, Sendable {
    case automatic = "automatic"
    case englishUS = "en-US"
    case englishUK = "en-GB"
    case portugueseBrazil = "pt-BR"
    case french = "fr-FR"
    case spanish = "es-ES"
    case german = "de-DE"
    case persian = "fa-IR"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .englishUS: "English (US)"
        case .englishUK: "English (UK)"
        case .portugueseBrazil: "Portuguese (Brazil)"
        case .french: "French"
        case .spanish: "Spanish"
        case .german: "German"
        case .persian: "Persian"
        }
    }

    /// nil lets Apple use the current macOS language and Whisper models auto-detect.
    public var localeIdentifier: String? { self == .automatic ? nil : rawValue }

    /// Settings are also exported by their visible catalog labels; accept either format.
    public init(persistedValue: String?) {
        self = Self.allCases.first { $0.rawValue == persistedValue || $0.title == persistedValue } ?? .automatic
    }

    /// whisper.cpp, faster-whisper and Parakeet expect a base language/script code.
    public static func engineLanguageCode(for localeIdentifier: String?) -> String? {
        guard let localeIdentifier, !localeIdentifier.isEmpty,
              localeIdentifier.caseInsensitiveCompare("automatic") != .orderedSame else { return nil }
        let normalized = localeIdentifier.replacingOccurrences(of: "_", with: "-")
        let code = normalized.split(separator: "-", maxSplits: 1).first.map(String.init) ?? normalized
        return code.isEmpty ? nil : code.lowercased()
    }
}

/// The speech-to-text engines ZEUS can dictate with. Apple is always there; the local
/// models need a one-time download and fall back to Apple until they are ready. The cloud
/// engines need the person's own key and are only used when chosen: audio leaves the Mac.
public enum TranscriptionEngineKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case parakeet, parakeetUltra, whisperKit, whisper, appleAnalyzer, apple, fasterWhisper
    case elevenLabs, openAI

    public var id: String { rawValue }

    /// Where an engine runs, for the grouped picker.
    public enum Group: String, CaseIterable, Sendable {
        case onThisMac = "On this Mac"
        case cloud = "Cloud"
    }

    public var group: Group { isCloud ? .cloud : .onThisMac }
    public var isCloud: Bool { self == .elevenLabs || self == .openAI }

    public static func engines(in group: Group) -> [TranscriptionEngineKind] { allCases.filter { $0.group == group } }

    public var title: String {
        switch self {
        case .parakeet: "Parakeet v3"
        case .parakeetUltra: "Parakeet Ultra"
        case .whisperKit: "Whisper turbo (WhisperKit)"
        case .whisper: "Whisper (whisper.cpp)"
        case .appleAnalyzer: "Apple SpeechAnalyzer"
        case .apple: "Apple on-device"
        case .fasterWhisper: "faster-whisper"
        case .elevenLabs: "ElevenLabs Scribe v2"
        case .openAI: "OpenAI gpt-transcribe"
        }
    }

    /// One honest line: speed, languages, size, and where the audio goes.
    public var detail: String {
        switch self {
        case .parakeet: "Fastest here, on the Neural Engine. 25 European languages including English, French and Portuguese. About 480 MB, downloaded once."
        case .parakeetUltra: "Parakeet v3 retrained by Moondream: fewer errors on every published test, same speed and 25 languages. About 630 MB."
        case .whisperKit: "Whisper large-v3 turbo on the Neural Engine. 99 languages and follows your vocabulary. About 630 MB."
        case .whisper: "Whisper on the Mac's GPU. 99 languages with the large model and follows your vocabulary. 150 MB to 570 MB."
        case .appleAnalyzer: "Apple's newer on-device model, macOS 26 and later. Quick and punctuated. macOS manages the download."
        case .apple: "Built into macOS. No download, works right away. Always the fallback."
        case .fasterWhisper: "Whisper in a private Python setup. Slower on Mac: CPU only, no Apple GPU or Neural Engine."
        case .elevenLabs: "Streams while you speak. 90+ languages. Uses your ElevenLabs key. Audio leaves this Mac."
        case .openAI: "Sent when you stop talking. Many languages, follows your vocabulary. Uses your OpenAI key. Audio leaves this Mac."
        }
    }

    public var needsDownload: Bool { group == .onThisMac && self != .apple }

    /// Approximate one-time download, when ZEUS fetches a fixed model.
    public var downloadMegabytes: Int? {
        switch self {
        case .parakeet: 480
        case .parakeetUltra: 630
        case .whisperKit: 630
        default: nil
        }
    }

    /// The Keychain account holding the key a cloud engine uses (existing slots only).
    public var keyAccount: String? {
        switch self {
        case .elevenLabs: "elevenlabs.api-key"
        case .openAI: "assistant.key.openAI"
        default: nil
        }
    }

    /// Engines that take names and jargon up front (a Whisper prompt, Apple contextual strings,
    /// cloud keyterms). The others still get the vocabulary's corrections afterwards.
    public var takesVocabulary: Bool {
        switch self {
        case .parakeet, .parakeetUltra, .appleAnalyzer: false
        default: true
        }
    }
}

/// Where an engine stands on this Mac.
public enum EngineAvailability: Equatable, Sendable {
    case ready
    case notDownloaded
    case downloading(Double)
    /// A cloud engine without its key in the Keychain.
    case needsKey
    /// Needs a newer macOS than this one.
    case needsNewerMacOS
    case unavailable(String)

    public var isReady: Bool { self == .ready }
}

/// A finished transcription and how long the engine took.
public struct Transcript: Equatable, Sendable {
    public var text: String
    public var engine: TranscriptionEngineKind
    /// Milliseconds spent decoding after the audio ended.
    public var latencyMs: Int

    public init(text: String, engine: TranscriptionEngineKind, latencyMs: Int) {
        self.text = text
        self.engine = engine
        self.latencyMs = latencyMs
    }
}

/// One speech-to-text backend. Audio is 16 kHz mono Float samples, the common input of
/// every engine ZEUS ships, so recording code never depends on which one is chosen.
public protocol TranscriptionEngine: Sendable {
    var kind: TranscriptionEngineKind { get }
    func availability() async -> EngineAvailability
    /// Load or download what the engine needs. Safe to call more than once.
    func prepare(progress: (@Sendable (Double) -> Void)?) async throws
    func transcribe(samples: [Float], hints: [String], language: String?) async throws -> String
}

/// Picks the engine to dictate with: the chosen one if it is ready, else the first ready
/// engine in `fallbackOrder` (Apple last, so dictation always works). Cloud engines are never
/// a fallback: audio only leaves the Mac when the person chose that engine.
public enum EngineSelection {
    public static let fallbackOrder: [TranscriptionEngineKind] = [.parakeet, .parakeetUltra, .whisperKit, .whisper, .appleAnalyzer, .fasterWhisper, .apple]

    public static func resolve(preferred: TranscriptionEngineKind,
                               availability: [TranscriptionEngineKind: EngineAvailability]) -> TranscriptionEngineKind {
        if availability[preferred]?.isReady == true { return preferred }
        return fallbackOrder.first { availability[$0]?.isReady == true } ?? .apple
    }
}

/// Runs the chosen engine and drops to the next ready one if it throws, so a broken model
/// never eats a dictation.
public struct TranscriptionRouter: Sendable {
    public let engines: [TranscriptionEngineKind: any TranscriptionEngine]
    private let clock: @Sendable () -> Date

    public init(engines: [any TranscriptionEngine], clock: @escaping @Sendable () -> Date = Date.init) {
        self.engines = Dictionary(engines.map { ($0.kind, $0) }, uniquingKeysWith: { first, _ in first })
        self.clock = clock
    }

    public func availability() async -> [TranscriptionEngineKind: EngineAvailability] {
        var result: [TranscriptionEngineKind: EngineAvailability] = [:]
        for (kind, engine) in engines { result[kind] = await engine.availability() }
        return result
    }

    public func transcribe(samples: [Float], preferred: TranscriptionEngineKind,
                           hints: [String] = [], language: String? = nil) async throws -> Transcript {
        let states = await availability()
        let first = EngineSelection.resolve(preferred: preferred, availability: states)
        let order = [first] + EngineSelection.fallbackOrder.filter { $0 != first && states[$0]?.isReady == true }
        var lastError: Error = TranscriptionError.noEngine
        for kind in order {
            guard let engine = engines[kind] else { continue }
            let started = clock()
            do {
                let text = try await engine.transcribe(samples: samples, hints: hints, language: language)
                let ms = Int(clock().timeIntervalSince(started) * 1000)
                return Transcript(text: text.trimmingCharacters(in: .whitespacesAndNewlines), engine: kind, latencyMs: ms)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

public enum TranscriptionError: LocalizedError, Equatable {
    case noEngine
    case notReady(TranscriptionEngineKind)
    case noSpeech

    public var errorDescription: String? {
        switch self {
        case .noEngine: "No speech engine is ready."
        case .notReady(let kind): kind.isCloud ? "\(kind.title) needs its key." : "\(kind.title) is not ready on this Mac yet."
        case .noSpeech: "No speech was heard."
        }
    }
}

/// Word error rate, the standard accuracy measure for speech recognition. Both texts are
/// lowercased, stripped of punctuation and split on whitespace before comparing.
public enum TranscriptMetrics {
    public static func normalizedWords(_ text: String) -> [String] {
        let folded = text.lowercased().folding(options: [.diacriticInsensitive], locale: nil)
        let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "'" ? Character($0) : " " }
        return String(cleaned).split(separator: " ").map { $0.replacingOccurrences(of: "'", with: "") }.filter { !$0.isEmpty }
    }

    /// (substitutions + deletions + insertions) / reference words. 0 is perfect.
    public static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        let ref = normalizedWords(reference)
        let hyp = normalizedWords(hypothesis)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        return Double(editDistance(ref, hyp)) / Double(ref.count)
    }

    static func editDistance(_ a: [String], _ b: [String]) -> Int {
        var previous = Array(0...b.count)
        for (i, wordA) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, wordB) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (wordA == wordB ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
