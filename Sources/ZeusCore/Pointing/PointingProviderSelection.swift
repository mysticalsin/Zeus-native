import Foundation

/// The three provider paths behind the one adapter seam.
public enum PointingProviderPath: String, CaseIterable, Codable, Sendable {
    /// Anthropic vision reasoning + ElevenLabs speech with timestamps.
    case anthropicElevenLabs
    /// OpenAI vision + OpenAI speech.
    case openAI
    /// The existing Zeus setup: the Any LLM route + system speech.
    case zeusSetup

    public var title: String {
        switch self {
        case .anthropicElevenLabs: "Anthropic + ElevenLabs"
        case .openAI: "OpenAI"
        case .zeusSetup: "Zeus setup"
        }
    }
}

/// The setting value. Auto is the default.
public enum PointingProviderChoice: String, CaseIterable, Sendable {
    case auto, anthropicElevenLabs, openAI, zeusSetup

    public static let settingTitles: [String: PointingProviderChoice] = [
        "Auto": .auto, "Anthropic + ElevenLabs": .anthropicElevenLabs, "OpenAI": .openAI, "Zeus setup": .zeusSetup,
    ]
    public init(setting: String?) { self = Self.settingTitles[setting ?? ""] ?? .auto }
    public var path: PointingProviderPath? {
        switch self {
        case .auto: nil
        case .anthropicElevenLabs: .anthropicElevenLabs
        case .openAI: .openAI
        case .zeusSetup: .zeusSetup
        }
    }
}

/// Time-to-first-token and time-to-first-audio per path. Numbers only, in RAM: no prompt,
/// transcript, image or response text is ever recorded here.
public struct PointingLatencyBook: Equatable, Sendable {
    public struct Stat: Equatable, Sendable {
        public var firstToken: Double?
        public var firstAudio: Double?
        public var samples = 0
        public var failedAt: TimeInterval?
        /// Exponential average, so one slow call does not pin a path for the session.
        static func blend(_ old: Double?, _ new: Double?) -> Double? {
            guard let new, new.isFinite, new >= 0 else { return old }
            return old.map { $0 * 0.6 + new * 0.4 } ?? new
        }
    }
    public static let failureCooldown: TimeInterval = 60
    public private(set) var stats: [PointingProviderPath: Stat] = [:]
    public init() {}

    public mutating func record(_ path: PointingProviderPath, firstToken: Double?, firstAudio: Double?) {
        var stat = stats[path] ?? Stat()
        stat.firstToken = Stat.blend(stat.firstToken, firstToken)
        stat.firstAudio = Stat.blend(stat.firstAudio, firstAudio)
        stat.samples += 1; stat.failedAt = nil
        stats[path] = stat
    }

    public mutating func recordFailure(_ path: PointingProviderPath, at now: TimeInterval) {
        var stat = stats[path] ?? Stat()
        stat.failedAt = now
        stats[path] = stat
    }

    public mutating func reset() { stats = [:] }

    /// Seconds to first audio, estimated as first token + first audio. nil until measured.
    public func score(_ path: PointingProviderPath) -> Double? {
        guard let stat = stats[path], stat.samples > 0, let token = stat.firstToken else { return nil }
        return token + (stat.firstAudio ?? 0)
    }

    func isCoolingDown(_ path: PointingProviderPath, at now: TimeInterval) -> Bool {
        guard let failed = stats[path]?.failedAt else { return false }
        return now - failed < Self.failureCooldown
    }
}

public enum PointingProviderSelector {
    public static let defaultOrder: [PointingProviderPath] = [.anthropicElevenLabs, .openAI, .zeusSetup]

    /// The paths to try, in order. `credentials`: paths whose keys exist (Keychain presence only).
    /// `health`: result of the cheap probe; a missing entry means "not probed, assume fine".
    ///
    /// An explicit choice is used alone and never silently replaced: a failure is reported.
    /// Auto takes the paths that have credentials and pass the probe, puts measured paths first by
    /// lowest latency, then the rest in the default order. A path that failed in the last minute
    /// goes last, so the next attempt tries something else first.
    public static func order(choice: PointingProviderChoice, credentials: Set<PointingProviderPath>,
                             health: [PointingProviderPath: Bool] = [:], latency: PointingLatencyBook = .init(),
                             now: TimeInterval = 0) -> [PointingProviderPath] {
        if let only = choice.path { return credentials.contains(only) ? [only] : [] }
        let usable = defaultOrder.filter { credentials.contains($0) && health[$0] != false }
        let measured = usable.filter { latency.score($0) != nil }
            .sorted { (latency.score($0) ?? 0) < (latency.score($1) ?? 0) }
        let unmeasured = usable.filter { latency.score($0) == nil }
        let ordered = measured + unmeasured
        return ordered.filter { !latency.isCoolingDown($0, at: now) } + ordered.filter { latency.isCoolingDown($0, at: now) }
    }
}
