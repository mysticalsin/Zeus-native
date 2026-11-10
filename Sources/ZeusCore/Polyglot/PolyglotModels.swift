import Foundation

/// Where Polyglot listens: the microphone, the audio playing on the Mac, or both.
public enum PolyglotSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case microphone, system, both

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .microphone: "Microphone"
        case .system: "Mac audio"
        case .both: "Both"
        }
    }

    public var symbol: String {
        switch self {
        case .microphone: "mic.fill"
        case .system: "speaker.wave.2.fill"
        case .both: "waveform.badge.mic"
        }
    }

    public var usesMicrophone: Bool { self != .system }
    /// System audio needs Screen Recording / System Audio permission; only this mode asks for it.
    public var usesSystemAudio: Bool { self != .microphone }
}

/// Which input a caption came from.
public enum PolyglotSide: String, Codable, Sendable {
    case microphone, system

    public var label: String { self == .microphone ? "You" : "Mac" }
}

/// A language Polyglot can translate into, by the base code Apple's Translation framework takes.
public struct PolyglotLanguage: Hashable, Identifiable, Sendable {
    public let code: String
    public let name: String
    public var id: String { code }

    public static let targets: [PolyglotLanguage] = [
        ("en", "English"), ("es", "Spanish"), ("pt", "Portuguese"), ("fr", "French"), ("de", "German"), ("it", "Italian"),
        ("nl", "Dutch"), ("pl", "Polish"), ("tr", "Turkish"), ("ru", "Russian"), ("uk", "Ukrainian"), ("ar", "Arabic"),
        ("hi", "Hindi"), ("id", "Indonesian"), ("th", "Thai"), ("vi", "Vietnamese"), ("ja", "Japanese"), ("ko", "Korean"),
        ("zh-Hans", "Chinese (Simplified)"), ("zh-Hant", "Chinese (Traditional)"),
    ].map { PolyglotLanguage(code: $0.0, name: $0.1) }

    public static func name(for code: String) -> String {
        targets.first { $0.code == code }?.name
            ?? Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    /// The 25 languages Parakeet v3 transcribes. Anything else goes to Apple's recognizer once its language is known.
    public static let parakeetLanguages: Set<String> = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it", "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
    ]

    /// "pt-BR" and "PT" both become "pt"; Chinese keeps its script.
    public static func base(_ code: String) -> String {
        let lowered = code.replacingOccurrences(of: "_", with: "-")
        if lowered.lowercased().hasPrefix("zh") { return lowered.lowercased().contains("hant") || lowered.lowercased().contains("tw") ? "zh-Hant" : "zh-Hans" }
        return String(lowered.split(separator: "-").first ?? "").lowercased()
    }

    /// The badge on a caption: "PT".
    public static func badge(_ code: String) -> String { base(code).prefix(2).uppercased() }
}

/// One caption: what was said, in which language, and what it means in the target language.
public struct PolyglotLine: Identifiable, Equatable, Sendable {
    public var id: Int
    public var side: PolyglotSide
    public var original: String
    public var language: String?
    public var translation: String?
    /// A partial is still being said; it settles to a final.
    public var isFinal: Bool
    /// The original is already in the target language, so there is nothing to translate.
    public var isTarget: Bool
    public var date: Date

    public init(id: Int, side: PolyglotSide, original: String, language: String?, translation: String? = nil,
                isFinal: Bool = true, isTarget: Bool = false, date: Date = Date()) {
        self.id = id
        self.side = side
        self.original = original
        self.language = language
        self.translation = translation
        self.isFinal = isFinal
        self.isTarget = isTarget
        self.date = date
    }
}

/// The running transcript: lines in order, a few for the card, all for "Copy transcript".
public struct PolyglotTranscript: Equatable, Sendable {
    public private(set) var lines: [PolyglotLine] = []
    public static let keep = 400

    public init(lines: [PolyglotLine] = []) { self.lines = lines }

    public mutating func upsert(_ line: PolyglotLine) {
        if let index = lines.firstIndex(where: { $0.id == line.id }) {
            lines[index] = line
        } else {
            // Ids rise in the order things were said: a caption from a run that was still draining lands
            // before the newer run's lines, not after them.
            let at = lines.lastIndex(where: { $0.id < line.id }).map { $0 + 1 } ?? 0
            lines.insert(line, at: at)
            if lines.count > Self.keep { lines.removeFirst(lines.count - Self.keep) }
        }
    }

    /// The same settled-caption writes the live controller applies. Partials and errors stay in the UI.
    public mutating func applySettled(_ event: PolyglotEvent) {
        switch event {
        case .line(let line): upsert(line)
        case .translated(let id, let text, _): setTranslation(id: id, text)
        case .partial, .discarded, .needsPack, .failed, .cleared: break
        }
    }

    public mutating func setTranslation(id: Int, _ text: String) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].translation = text
    }

    /// A new destination must never label an old translation as the new language.
    /// Originals remain available while the controller translates them again.
    public mutating func retarget(to target: String) {
        let language = PolyglotLanguage.base(target)
        for index in lines.indices {
            lines[index].translation = nil
            lines[index].isTarget = lines[index].language.map { PolyglotLanguage.base($0) == language } ?? false
        }
    }

    public mutating func clear() { lines.removeAll() }

    public func recent(_ count: Int) -> [PolyglotLine] { Array(lines.suffix(count)) }

    /// Plain text for the clipboard: "[PT] original" then "→ translation".
    public func text(target: String) -> String {
        lines.filter(\.isFinal).map { line in
            var out = line.language.map { "[\(PolyglotLanguage.badge($0))] " } ?? ""
            out += line.original
            if let translation = line.translation, !translation.isEmpty, !line.isTarget { out += "\n→ \(translation)" }
            return out
        }.joined(separator: "\n")
    }
}

/// The line being said right now, per input. Every utterance has an id (the id of the line it becomes):
/// a partial is taken only for the input's current utterance, a final or discard for utterance N retires
/// N's partial (and nothing newer), and anything for an utterance already finished is dropped.
public struct PolyglotLivePartials: Equatable, Sendable {
    public private(set) var texts: [PolyglotSide: String] = [:]
    private var ids: [PolyglotSide: Int] = [:]
    private var finished: [PolyglotSide: Int] = [:]

    public init() {}

    @discardableResult
    public mutating func applyPartial(side: PolyglotSide, id: Int, text: String) -> Bool {
        guard id > (finished[side] ?? 0), id >= (ids[side] ?? 0) else { return false }
        ids[side] = id
        texts[side] = text
        return true
    }

    /// Utterance `id` ended (a final line, or no caption at all).
    public mutating func settle(side: PolyglotSide, id: Int) {
        finished[side] = max(finished[side] ?? 0, id)
        if let current = ids[side], current <= id {
            ids[side] = nil
            texts[side] = nil
        }
    }

    /// Hides what is being said (Stop, Clear) but still remembers which utterances ended.
    public mutating func dropPartials() {
        texts = [:]
        ids = [:]
    }

    /// A new run: its ids start over.
    public mutating func reset() {
        dropPartials()
        finished = [:]
    }
}

/// Captions the speech engines invent from silence or room noise; dropped before they reach the card.
public enum PolyglotTextFilter {
    private static let phantoms: [String] = [
        "thanks for watching", "thank you for watching", "subtitles by", "subtitles made by", "amara.org", "please subscribe",
        "obrigado por assistir", "legendas pela comunidade", "subtítulos por", "subtitulos por", "gracias por ver",
        "merci d'avoir regardé", "sous-titres", "untertitel", "like and subscribe", "you",
    ]

    public static func isPhantom(_ text: String) -> Bool {
        let cleaned = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if cleaned.isEmpty { return true }
        if cleaned.unicodeScalars.allSatisfy({ !CharacterSet.letters.contains($0) && !CharacterSet.decimalDigits.contains($0) }) { return true }
        return phantoms.contains { phantom in cleaned == phantom || (phantom.count > 8 && cleaned.hasPrefix(phantom)) }
    }
}

/// Caption text size from Settings.
public enum PolyglotCaptionSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    /// Points for the translated line; the original is smaller.
    public var translationPoints: Double { self == .small ? 14 : self == .medium ? 17 : 21 }
    public var originalPoints: Double { self == .small ? 11 : self == .medium ? 13 : 16 }
}
