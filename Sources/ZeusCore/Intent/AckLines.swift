import Foundation

/// What a fast action is about to do, for the short spoken acknowledgement.
public enum FastAck: Equatable, Sendable {
    case opening(String)
    case switching(String)
    case quitting(String)
    case hiding(String)
    case notRunning(String)
    case notInstalled(String)
    case searchingSpotify(String)
    case resumingSpotify
    case media(FastIntent.Media)
    case volume(FastIntent.Volume)
    case added([String])
    case eventAdded(String)
    case openingSite(String)
    case locking
    case timer(seconds: Int)
    case timerCancelled
    case terminal(project: String?)
    case project(String, FastIntent.ProjectApp)
    case agent(CodingTool, project: String?)
    case research(String, deep: Bool)
    case polyglot(start: Bool)
}

/// The lines Zeus says when it acts on the fast path. `persona` routes to the persona line bank
/// (`ZeusVoiceLines`, Ultron or Plain); `neutral` is the plain fallback and covers what the bank
/// has no situation for (timers, "isn't open"). Returning nil says nothing (the notch cue is enough).
public struct AckLines: Sendable {
    public var line: @Sendable (FastAck) -> String?

    public init(line: @escaping @Sendable (FastAck) -> String?) { self.line = line }

    public static let neutral = AckLines { ack in
        Self.clamp(Self.rawNeutral(ack))
    }

    private static func rawNeutral(_ ack: FastAck) -> String? {
        switch ack {
        case .opening(let app): "Opening \(app)."
        case .switching(let app): "\(app)."
        case .quitting(let app): "Quitting \(app)."
        case .hiding(let app): "Hiding \(app)."
        case .notRunning(let app): "\(app) isn't open."
        case .notInstalled(let app): "\(app) isn't installed."
        case .searchingSpotify(let query): "Playing \(query) on Spotify."
        case .resumingSpotify: "Spotify."
        case .media(let command):
            switch command {
            case .play: "Playing."
            case .pause: "Paused."
            case .toggle: "Play or pause."
            case .next: "Next track."
            case .previous: "Previous track."
            }
        case .volume, .locking: nil
        case .eventAdded(let title): "Added \(title) to your calendar."
        case .added(let items): items.count == 1 ? "Added \(items[0])." : "Added \(items.count) to-dos."
        case .openingSite(let host): "Opening \(host)."
        case .timer(let seconds): "Timer set for \(AckLines.spoken(seconds))."
        case .timerCancelled: "Timer cancelled."
        case .terminal(let project): project.map { "Opening a terminal in \($0)." } ?? "Opening a terminal."
        case .project(let name, let app): "Opening \(name) in \(app == .vscode ? "VS Code" : app.rawValue.capitalized)."
        case .agent(let tool, let project): "Starting \(tool.title)\(project.map { " in \($0)" } ?? "")."
        case .research(let topic, let deep): deep ? "Researching \(topic) in depth." : "Looking into \(topic)."
        case .polyglot(let start): start ? "Starting live translation." : "Stopping live translation."
        }
    }

    /// The persona's lines where `ZeusVoiceLines` has a situation, neutral ones elsewhere.
    public static let persona = AckLines { ack in
        Self.clamp(Self.rawPersona(ack) { ZeusVoiceLines.line(for: $0, context: $1) })
    }

    /// Explicit inputs avoid consulting host preferences or sharing the live line bank.
    public static func persona(personality: ZeusPersonality, lines: ZeusVoiceLines = ZeusVoiceLines()) -> AckLines {
        AckLines { ack in
            Self.clamp(Self.rawPersona(ack) { lines.line(for: $0, context: $1, personality: personality) })
        }
    }

    private static func rawPersona(_ ack: FastAck, line: (ZeusVoiceLines.Situation, [String: String]) -> String) -> String? {
        switch ack {
        case .opening(let app), .switching(let app):
            line(.ackOpen, ["app": app])
        case .searchingSpotify(let query):
            line(.ackPlay, ["artist": query])
        case .resumingSpotify, .media(.play):
            line(.ackPlay, [:])
        case .media(.pause), .media(.toggle):
            line(.ackDone, [:])
        case .media(.next), .media(.previous):
            line(.ackDone, [:])
        case .added(let items):
            line(.ackTodoAdded, items.count == 1 ? ["item": items[0]] : [:])
        case .quitting, .hiding, .openingSite:
            line(.ackDone, [:])
        default:
            rawNeutral(ack)
        }
    }

    /// Truncates `text` to at most `words` words, at a word boundary, replacing any trailing
    /// punctuation with a single period so a clamp never reads as a mid-thought cut-off. `nil`
    /// passes through unchanged. Guards against unbounded spliced text (a very long app, playlist
    /// or to-do name) blowing an otherwise-short ack past the persona's one-clause limit.
    public static func clamp(_ text: String?, words: Int = 10) -> String? {
        guard let text else { return nil }
        let parts = text.split(separator: " ")
        guard parts.count > words else { return text }
        let truncated = parts.prefix(words).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        return truncated + "."
    }

    /// "5 minutes", "1 hour 30 minutes", "45 seconds".
    public static func spoken(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        var parts: [String] = []
        if h > 0 { parts.append(h == 1 ? "1 hour" : "\(h) hours") }
        if m > 0 { parts.append(m == 1 ? "1 minute" : "\(m) minutes") }
        if s > 0 { parts.append(s == 1 ? "1 second" : "\(s) seconds") }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }
}
