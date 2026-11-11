import Foundation

/// The stages of one spoken turn, in the order they normally happen. Raw values are the `key=` names
/// in the `[ZEUS] voice-latency` log line that `scripts/voice-latency.sh` reads.
public enum VoiceStage: String, CaseIterable, Sendable {
    case keyUp = "key_up"
    case transcriptFinal = "transcript"
    case requestSent = "request"
    case firstToken = "first_token"
    case firstSentence = "first_sentence"
    case ttsRequest = "tts_request"
    case firstAudio = "first_audio"
    case turnEnd = "turn_end"
}

/// One latency trace per voice turn. Times are milliseconds since key-up (or since the transcript for a
/// wake or typed turn), the first mark for a stage wins, and the log line never holds the transcript,
/// the answer or any key.
public struct VoiceLatencyTrace: Sendable, Equatable {
    public private(set) var marks: [VoiceStage: Int] = [:]
    public var brainEngine = "-"
    public var model = "-"
    public var ttsEngine = "-"
    public var voice = "-"
    public var reason = "-"
    public var effectPercent: Int?
    public let turnID: String

    public init(turnID: String = UUID().uuidString.prefix(8).lowercased()) {
        self.turnID = turnID
        marks[.keyUp] = 0
    }

    /// Records a stage once. A later mark for the same stage, or a negative time, is ignored/clamped.
    public mutating func mark(_ stage: VoiceStage, atMs: Int) {
        guard marks[stage] == nil else { return }
        marks[stage] = max(0, atMs)
    }

    public func ms(_ stage: VoiceStage) -> Int? { marks[stage] }

    /// The headline figure: talk key released to the first audio buffer scheduled for playback.
    public var keyUpToFirstAudioMs: Int? { marks[.firstAudio] }

    /// True once the turn reached `.firstAudio` or `.turnEnd`, so the log line is worth writing.
    public var isComplete: Bool { marks[.turnEnd] != nil }

    static func clean(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "-" : String(trimmed.prefix(140))
    }

    /// `turn=ab12cd34 key_up=0 transcript=310 ... first_audio=1420 turn_end=4800 ttfa=1420 brain=... reason="..."`.
    /// A stage that never happened prints `-`.
    public var logDetail: String {
        var parts = ["turn=\(turnID)"]
        for stage in VoiceStage.allCases {
            parts.append("\(stage.rawValue)=\(marks[stage].map(String.init) ?? "-")")
        }
        parts.append("ttfa=\(keyUpToFirstAudioMs.map(String.init) ?? "-")")
        parts.append("brain=\(Self.clean(brainEngine).replacingOccurrences(of: " ", with: "_"))")
        parts.append("model=\(Self.clean(model).replacingOccurrences(of: " ", with: "_"))")
        parts.append("tts=\(Self.clean(ttsEngine).replacingOccurrences(of: " ", with: "_"))")
        parts.append("voice=\(Self.clean(voice).replacingOccurrences(of: " ", with: "_"))")
        parts.append("effect=\(effectPercent.map(String.init) ?? "-")")
        parts.append("reason=\"\(Self.clean(reason))\"")
        return parts.joined(separator: " ")
    }
}

/// How fast a turn should be, per route. Used by the Settings "Test voice" button and by the docs.
public enum VoiceLatencyTargets {
    /// Key-up to first audio with a direct API brain and a cloud voice.
    public static let apiCloudVoiceMs = 1_200
    /// Key-up to first audio with only the CLI brains (and any voice).
    public static let cliOnlyMs = 2_500

    public static func targetMs(apiBrain: Bool, cloudVoice: Bool) -> Int {
        apiBrain && cloudVoice ? apiCloudVoiceMs : cliOnlyMs
    }

    /// The "Test voice" button measures only the voice leg (no brain), so it compares against this.
    public static let voiceLegMs = 600

    public static func voiceLegVerdict(ms: Int) -> String {
        ms <= voiceLegMs ? "fast (\(ms) ms)" : "slow (\(ms) ms, target \(voiceLegMs) ms)"
    }
}

/// Which warm-up the talk key press should trigger. Never at launch: the key going down is the signal that
/// a turn is about to happen, and the user is still speaking for a second or two.
public enum KeyDownWarm: Sendable, Equatable { case anthropicAPI, openAIAPI, claudeCLI }

public struct VoiceTurnKeys: Sendable, Equatable {
    public var anthropicKey: Bool
    public var openAIKey: Bool
    public var claudeCLI: Bool
    public var codexCLI: Bool

    public init(anthropicKey: Bool = false, openAIKey: Bool = false, claudeCLI: Bool = false, codexCLI: Bool = false) {
        self.anthropicKey = anthropicKey
        self.openAIKey = openAIKey
        self.claudeCLI = claudeCLI
        self.codexCLI = codexCLI
    }
}

public enum VoiceTurnRoute {
    public struct Brain: Sendable, Equatable {
        public var path: String
        public var model: String
        public var reason: String
        public var warm: [KeyDownWarm]
    }

    /// The fastest brain for a spoken answer given what is saved. API first (direct streaming, one warm
    /// connection), then the CLIs (a persistent lean process), nothing when none is installed.
    public static func brain(_ keys: VoiceTurnKeys) -> Brain {
        if keys.anthropicKey {
            return Brain(path: "anthropic-api", model: ModelCap.httpModel(.anthropic, tier: .fast) ?? "-",
                         reason: "Anthropic key saved: direct streaming", warm: [.anthropicAPI])
        }
        if keys.openAIKey {
            return Brain(path: "openai", model: ModelCap.httpModel(.openAI, tier: .fast) ?? "-",
                         reason: "OpenAI key saved: direct streaming", warm: [.openAIAPI])
        }
        if keys.claudeCLI {
            return Brain(path: "claude-cli", model: ModelCap.model(for: .claude, tier: .fast) ?? "-",
                         reason: "no API key: persistent lean Claude CLI", warm: [.claudeCLI])
        }
        if keys.codexCLI {
            return Brain(path: "codex-cli", model: "-", reason: "no API key and no Claude CLI: Codex CLI", warm: [])
        }
        return Brain(path: "none", model: "-", reason: "no API key and no CLI installed", warm: [])
    }

    /// Both the brain and the voice have a direct cloud route, so the 1.2 s target applies.
    public static func targetMs(_ keys: VoiceTurnKeys, cloudVoice: Bool) -> Int {
        VoiceLatencyTargets.targetMs(apiBrain: keys.anthropicKey || keys.openAIKey, cloudVoice: cloudVoice)
    }
}

/// When a persistent `claude` process can serve the next turn, and when it is replaced. A long-lived
/// process keeps its own conversation, so it is recycled every few turns to keep prompts small, and
/// whenever the wanted launch flags change (fast and deep tiers use different models).
public enum PersistentCLIPolicy {
    public static let maxTurns = 5
    public static let maxAgeSeconds: TimeInterval = 20 * 60

    public struct Slot: Sendable, Equatable {
        public var launchKey: String
        public var turnsServed: Int
        public var startedAt: Date
        public var alive: Bool

        public init(launchKey: String, turnsServed: Int, startedAt: Date, alive: Bool) {
            self.launchKey = launchKey
            self.turnsServed = turnsServed
            self.startedAt = startedAt
            self.alive = alive
        }
    }

    public enum Action: Sendable, Equatable { case reuse, respawn }

    public static func action(existing: Slot?, wantedKey: String, now: Date) -> Action {
        guard let slot = existing, slot.alive, slot.launchKey == wantedKey,
              slot.turnsServed < maxTurns, now.timeIntervalSince(slot.startedAt) < maxAgeSeconds else { return .respawn }
        return .reuse
    }
}
