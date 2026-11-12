import Foundation

/// Chooses the deepest male macOS voice for the Ultron persona. Never Samantha, never a female
/// or novelty voice. Pure, so it is tested without AVFoundation.
public enum UltronSystemVoicePick {
    public struct Candidate: Equatable, Sendable {
        public var name: String
        public var language: String
        /// 1 default, 2 enhanced, 3 premium (AVSpeechSynthesisVoiceQuality raw values).
        public var quality: Int
        public var identifier: String
        public init(name: String, language: String, quality: Int, identifier: String) {
            self.name = name
            self.language = language
            self.quality = quality
            self.identifier = identifier
        }
    }

    /// Deep male voices, deepest and most natural first.
    public static let preferredNames = [
        "Evan", "Tom", "Aaron", "Nathan", "Alex", "Daniel", "Oliver", "Arthur", "Gordon", "Lee",
        "Reed", "Thomas", "Jacques", "Diego", "Jorge", "Luca", "Fred", "Rishi", "Eddy", "Rocko",
    ]

    /// Never chosen: Samantha, every female voice we know, and the novelty voices.
    public static let denied: Set<String> = [
        "samantha", "karen", "moira", "tessa", "fiona", "kathy", "victoria", "allison", "ava", "susan",
        "zoe", "nicky", "flo", "sandy", "shelley", "grandma", "bubbles", "bells", "boing", "bad news",
        "bahh", "cellos", "good news", "jester", "wobble", "organ", "superstar", "trinoids", "whisper",
        "zarvox", "albert", "junior", "princess", "kate", "serena", "stephanie", "veena", "alice",
        "amelie", "anna", "paulina", "monica", "joana", "milena", "carmit", "ellen", "laura",
    ]

    public static func isAllowed(_ candidate: Candidate) -> Bool {
        !denied.contains(candidate.name.lowercased())
    }

    /// The best allowed voice for `languageCode` (for example "en-CA"), or nil when none qualifies.
    public static func pick(from candidates: [Candidate], languageCode: String) -> Candidate? {
        let prefix = String(languageCode.prefix(2)).lowercased()
        let exact = languageCode.replacingOccurrences(of: "_", with: "-").lowercased()
        let pool = candidates.filter { isAllowed($0) && $0.language.lowercased().hasPrefix(prefix) }
        func score(_ c: Candidate) -> Int {
            let rank = preferredNames.firstIndex { $0.caseInsensitiveCompare(c.name) == .orderedSame }
            let nameScore = rank.map { 100 - $0 * 3 } ?? 0
            return c.quality * 1_000 + nameScore + (c.language.lowercased() == exact ? 5 : 0)
        }
        // Only a voice we know to be a deep male one, or any unknown-but-allowed voice, in score order.
        return pool.max { score($0) < score($1) }
    }

    /// True when the best usable Mac voice is only the default tier, so Settings can suggest installing an
    /// Enhanced or Premium voice. Nothing is downloaded automatically.
    public static func suggestsBetterVoice(from candidates: [Candidate], languageCode: String) -> Bool {
        guard let best = pick(from: candidates, languageCode: languageCode) else { return true }
        return best.quality < 2
    }

    /// The word for a quality tier, as shown in Settings.
    public static func tierName(_ quality: Int) -> String {
        switch quality {
        case 3...: "Premium"
        case 2: "Enhanced"
        default: "Default"
        }
    }

    /// Slower than normal speech, never fast: the measured pacing of the persona.
    public static func rate(defaultRate: Float) -> Float { max(0.1, defaultRate * 0.92) }
    public static let pitchMultiplier: Float = 0.82
}
