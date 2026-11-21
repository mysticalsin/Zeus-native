import Foundation

/// How a local quit is delivered. The save dialog needs the Quit Apple event, not `terminate()`.
public enum LocalQuitAction: Equatable, Sendable {
    case appleEvent(interact: Bool, waitForReply: Bool)
}

public enum LocalQuit {
    public static let action = LocalQuitAction.appleEvent(interact: true, waitForReply: false)
}

/// One installed app, supplied by the caller. The machine never looks a name up itself.
public struct LocalApp: Equatable, Sendable {
    public var name: String
    public var bundleID: String
    public var path: String
    public var aliases: [String]
    public var isRunning: Bool
    /// `true` dirty, `false` known clean, `nil` unknown. Unknown asks before a quit.
    public var hasUnsavedState: Bool?

    public init(name: String, bundleID: String, path: String = "", aliases: [String] = [],
                isRunning: Bool = false, hasUnsavedState: Bool? = nil) {
        self.name = name
        self.bundleID = bundleID
        self.path = path
        self.aliases = aliases
        self.isRunning = isRunning
        self.hasUnsavedState = hasUnsavedState
    }
}

public enum LocalAppVerb: Equatable, Sendable {
    case open, quit, switchTo
}

public enum LocalCommandAction: Equatable, Sendable {
    case open(LocalApp)
    case quit(LocalApp)
    case switchTo(LocalApp)
    case media(LocalMedia)
    case volume(LocalVolume)
}

public enum LocalCommandEffect: Equatable, Sendable {
    /// Start this action before speaking. The clock has already accepted it.
    case perform(LocalCommandAction)
    case speak(String)
    /// The transcript was not taken. The caller continues with the existing route.
    case fallThrough
}

public enum LocalCommandState: Equatable, Sendable {
    case idle
    case confirmingQuit(LocalApp)
    case confirmingChoice(LocalAppVerb, [LocalApp])
    case acted(LocalCommandAction)
}

public struct LocalCommandDecision: Equatable, Sendable {
    public var state: LocalCommandState
    public var effects: [LocalCommandEffect]
    /// Milliseconds from the final transcript to the clock reading. Nil only when the clock was not read.
    public var elapsedMilliseconds: Int?

    public var consumed: Bool {
        !effects.contains(.fallThrough)
    }
}

/// A clock the machine reads once per transcript. Tests pass a frozen instant.
public struct LocalCommandClock: Sendable {
    public var now: @Sendable () -> ContinuousClock.Instant

    public init(now: @escaping @Sendable () -> ContinuousClock.Instant) {
        self.now = now
    }

    public static let system = LocalCommandClock { ContinuousClock.now }
}

/// Paths the spoken catalog may name. The index can see more; this list does not.
public enum LocalAppCatalog {
    /// `/Applications` and the user's Applications folder, including anything inside them.
    /// A path that only shares a prefix with those roots is left out.
    public static func included(_ path: String, home: String) -> Bool {
        guard !path.isEmpty, !home.isEmpty else { return false }
        return inside(path, root: "/Applications")
            || inside(path, root: "/System/Applications")
            || inside(path, root: userApplications(home))
    }

    /// Lexical `..` and `.` are resolved before a root check, so a prefix cannot climb out.
    public static func standardized(_ path: String) -> String {
        let absolute = path.hasPrefix("/")
        var parts: [String] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." {
                if !parts.isEmpty { parts.removeLast() }
                continue
            }
            parts.append(String(part))
        }
        let joined = parts.joined(separator: "/")
        return absolute ? "/" + joined : joined
    }

    public static func userApplications(_ home: String) -> String {
        let trimmed = home.count > 1 && home.hasSuffix("/") ? String(home.dropLast()) : home
        return trimmed == "/" ? "/Applications" : trimmed + "/Applications"
    }

    private static func inside(_ path: String, root: String) -> Bool {
        let path = standardized(path)
        var root = standardized(root)
        if root.hasSuffix("/") { root = String(root.dropLast()) }
        return path == root || path.hasPrefix(root + "/")
    }
}

/// Deterministic local commands. One state, one clock reading, no I/O.
public struct LocalCommandMachine: Equatable, Sendable {
    public static let latencyBudgetMilliseconds = 150
    /// A quit confirmation dies at this age, or sooner if the next turn ends first.
    public static let quitConfirmationLifetimeMilliseconds = 10_000

    public private(set) var state: LocalCommandState
    private var quitAskedAt: ContinuousClock.Instant?
    /// Armed at the end of the turn that asked, so the following turn can drop the question.
    public private(set) var quitExpiresAtEndOfNextTurn = false

    public init() {
        state = .idle
    }

    public var isConfirmingQuit: Bool {
        if case .confirmingQuit = state { return true }
        return false
    }

    public mutating func reset() {
        state = .idle
        quitAskedAt = nil
        quitExpiresAtEndOfNextTurn = false
    }

    /// Call at the end of a turn that began with a quit confirmation already pending.
    /// A confirmation created during this turn is left for the turn after it.
    public mutating func endTurn() {
        if quitExpiresAtEndOfNextTurn, case .confirmingQuit = state {
            state = .idle
            quitAskedAt = nil
        }
        quitExpiresAtEndOfNextTurn = false
    }

    /// The question was asked on this turn. The next turn's `endTurn` drops it if it is still waiting.
    public mutating func armQuitExpiryAtEndOfNextTurn() {
        quitExpiresAtEndOfNextTurn = isConfirmingQuit
    }

    /// What a finished voice turn does. The controller calls this from the end of the turn.
    /// A question asked on this turn is armed. A question armed on the previous turn is dropped.
    public mutating func finishTurn() {
        if quitExpiresAtEndOfNextTurn {
            endTurn()
        } else if isConfirmingQuit {
            armQuitExpiryAtEndOfNextTurn()
        }
    }

    public mutating func receive(_ transcript: String, finalAt: ContinuousClock.Instant,
                                 clock: LocalCommandClock, apps: [LocalApp]) -> LocalCommandDecision {
        let now = clock.now()
        let elapsed = Self.elapsedMilliseconds(from: finalAt, to: now)
        guard elapsed < Self.latencyBudgetMilliseconds else {
            state = .idle
            quitAskedAt = nil
            quitExpiresAtEndOfNextTurn = false
            return decision(.idle, [.fallThrough], elapsed)
        }
        if case .confirmingQuit = state, let asked = quitAskedAt,
           Self.elapsedMilliseconds(from: asked, to: now) >= Self.quitConfirmationLifetimeMilliseconds {
            state = .idle
            quitAskedAt = nil
            quitExpiresAtEndOfNextTurn = false
            return receiveFresh(transcript, elapsed: elapsed, apps: apps, now: now)
        }
        switch state {
        case .confirmingQuit(let app):
            return receiveQuitReply(transcript, app: app, elapsed: elapsed, apps: apps, now: now)
        case .confirmingChoice(let verb, let candidates):
            return receiveChoiceReply(transcript, verb: verb, candidates: candidates, elapsed: elapsed, apps: apps, now: now)
        case .idle, .acted:
            state = .idle
            return receiveFresh(transcript, elapsed: elapsed, apps: apps, now: now)
        }
    }

    // MARK: Replies

    /// An explicit confirm. "ok", "sure", and a bare "quit" are not in this set.
    private static let yesWords: Set<String> = [
        "yes", "yeah", "yep", "yah", "confirm", "do it", "go ahead", "quit it", "please do", "okay",
    ]

    private static let noWords: Set<String> = [
        "no", "nope", "nah", "cancel", "dont", "do not", "stop", "never mind", "leave it", "leave it open",
    ]

    private mutating func receiveQuitReply(_ transcript: String, app: LocalApp, elapsed: Int, apps: [LocalApp],
                                           now: ContinuousClock.Instant) -> LocalCommandDecision {
        let words = LocalCommandParser.normalize(transcript)
        if Self.yesWords.contains(words) {
            return act(.quit(app), line: "Quitting \(app.name).", elapsed: elapsed)
        }
        if Self.noWords.contains(words) {
            state = .idle
            quitAskedAt = nil
            quitExpiresAtEndOfNextTurn = false
            return decision(.idle, [.speak("Leaving it open.")], elapsed)
        }
        if LocalCommandParser.parse(transcript) != nil {
            state = .idle
            quitAskedAt = nil
            quitExpiresAtEndOfNextTurn = false
            return receiveFresh(transcript, elapsed: elapsed, apps: apps, now: now)
        }
        state = .idle
        quitAskedAt = nil
        quitExpiresAtEndOfNextTurn = false
        return decision(.idle, [.fallThrough], elapsed)
    }

    private mutating func receiveChoiceReply(_ transcript: String, verb: LocalAppVerb, candidates: [LocalApp],
                                             elapsed: Int, apps: [LocalApp], now: ContinuousClock.Instant) -> LocalCommandDecision {
        let words = LocalCommandParser.normalize(transcript)
        if Self.noWords.contains(words) {
            state = .idle
            return decision(.idle, [.speak("Okay.")], elapsed)
        }
        if LocalCommandParser.parse(transcript) != nil {
            state = .idle
            return receiveFresh(transcript, elapsed: elapsed, apps: apps, now: now)
        }
        let hits = Self.match(words, in: candidates)
        switch hits.count {
        case 0:
            state = .idle
            return decision(.idle, [.fallThrough], elapsed)
        case 1:
            return resolve(hits[0], verb: verb, elapsed: elapsed, now: now)
        default:
            return askChoice(verb, hits, elapsed: elapsed, now: now)
        }
    }

    // MARK: Fresh transcript

    private mutating func receiveFresh(_ transcript: String, elapsed: Int, apps: [LocalApp],
                                       now: ContinuousClock.Instant) -> LocalCommandDecision {
        guard let command = LocalCommandParser.parse(transcript) else {
            return decision(.idle, [.fallThrough], elapsed)
        }
        switch command {
        case .media(let media):
            let line = switch media {
            case .play: "Playing."
            case .pause: "Paused."
            case .next: "Next."
            }
            return act(.media(media), line: line, elapsed: elapsed)
        case .volume(let volume):
            let line = switch volume {
            case .up: "Louder."
            case .down: "Quieter."
            case .mute: "Muted."
            case .unmute: "Unmuted."
            case .set(let value): "Volume \(value)."
            }
            return act(.volume(volume), line: line, elapsed: elapsed)
        case .open(let query):
            return resolveQuery(query, verb: .open, elapsed: elapsed, apps: apps, now: now)
        case .quit(let query):
            return resolveQuery(query, verb: .quit, elapsed: elapsed, apps: apps, now: now)
        case .switchTo(let query):
            return resolveQuery(query, verb: .switchTo, elapsed: elapsed, apps: apps, now: now)
        }
    }

    private mutating func resolveQuery(_ query: String, verb: LocalAppVerb, elapsed: Int, apps: [LocalApp],
                                       now: ContinuousClock.Instant) -> LocalCommandDecision {
        let hits = Self.match(query, in: apps)
        switch hits.count {
        case 0:
            return decision(.idle, [.fallThrough], elapsed)
        case 1:
            return resolve(hits[0], verb: verb, elapsed: elapsed, now: now)
        default:
            return askChoice(verb, hits, elapsed: elapsed, now: now)
        }
    }

    private mutating func resolve(_ app: LocalApp, verb: LocalAppVerb, elapsed: Int,
                                  now: ContinuousClock.Instant) -> LocalCommandDecision {
        switch verb {
        case .open:
            return act(.open(app), line: "Opening \(app.name).", elapsed: elapsed)
        case .switchTo:
            return act(.switchTo(app), line: "Switching to \(app.name).", elapsed: elapsed)
        case .quit:
            guard app.isRunning else {
                state = .idle
                quitAskedAt = nil
                quitExpiresAtEndOfNextTurn = false
                return decision(.idle, [.speak("\(app.name) isn't open.")], elapsed)
            }
            guard app.hasUnsavedState == false else {
                state = .confirmingQuit(app)
                quitAskedAt = now
                quitExpiresAtEndOfNextTurn = false
                return decision(state, [.speak("Quit \(app.name)? It may have unsaved changes.")], elapsed)
            }
            return act(.quit(app), line: "Quitting \(app.name).", elapsed: elapsed)
        }
    }

    private mutating func askChoice(_ verb: LocalAppVerb, _ apps: [LocalApp], elapsed: Int,
                                    now: ContinuousClock.Instant) -> LocalCommandDecision {
        _ = now
        state = .confirmingChoice(verb, apps)
        quitAskedAt = nil
        quitExpiresAtEndOfNextTurn = false
        return decision(state, [.speak(Self.choicePrompt(apps.map(\.name)))], elapsed)
    }

    private mutating func act(_ action: LocalCommandAction, line: String, elapsed: Int) -> LocalCommandDecision {
        state = .acted(action)
        quitAskedAt = nil
        quitExpiresAtEndOfNextTurn = false
        return decision(state, [.perform(action), .speak(line)], elapsed)
    }

    private func decision(_ state: LocalCommandState, _ effects: [LocalCommandEffect], _ elapsed: Int) -> LocalCommandDecision {
        LocalCommandDecision(state: state, effects: effects, elapsedMilliseconds: elapsed)
    }

    // MARK: Catalog

    /// Exact name or alias, else a space-bounded prefix. Exact hits suppress prefixes.
    public static func match(_ query: String, in apps: [LocalApp]) -> [LocalApp] {
        let wanted = LocalCommandParser.normalize(query)
        guard wanted.count >= 2 else { return [] }
        var exact: [LocalApp] = []
        var prefixed: [LocalApp] = []
        var seen = Set<String>()
        for app in apps {
            let identity = app.bundleID.isEmpty ? app.path + app.name : app.bundleID
            guard seen.insert(identity).inserted else { continue }
            let keys = [app.name] + app.aliases
            let normalised = keys.map(LocalCommandParser.normalize).filter { !$0.isEmpty }
            if normalised.contains(wanted) {
                exact.append(app)
            } else if normalised.contains(where: { $0.hasPrefix(wanted + " ") }) {
                prefixed.append(app)
            }
        }
        return sort(exact.isEmpty ? prefixed : exact)
    }

    public static func choicePrompt(_ names: [String]) -> String {
        switch names.count {
        case 0: "Which one?"
        case 1: "Did you mean \(names[0])?"
        case 2: "Did you mean \(names[0]) or \(names[1])?"
        default:
            "Did you mean \(names.dropLast().joined(separator: ", ")), or \(names[names.count - 1])?"
        }
    }

    private static func sort(_ apps: [LocalApp]) -> [LocalApp] {
        apps.sorted { lhs, rhs in
            let order = lhs.name.lowercased().compare(rhs.name.lowercased(), locale: Locale(identifier: "en"))
            if order == .orderedSame { return lhs.bundleID < rhs.bundleID }
            return order == .orderedAscending
        }
    }

    /// Whole milliseconds, never negative. A clock behind `finalAt` counts as zero.
    public static func elapsedMilliseconds(from finalAt: ContinuousClock.Instant, to now: ContinuousClock.Instant) -> Int {
        let components = (now - finalAt).components
        let milliseconds = components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
        return Int(max(0, milliseconds))
    }
}

/// Play resumes a paused session in place. Otherwise Spotify, when it is installed.
public enum MediaPlayPolicy {
    public enum Choice: Equatable, Sendable { case mediaKey, resumeSpotify }

    /// A session that is already playing or paused stays on the media key. Spotify is only the fallback when nothing is loaded.
    public static func choose(hasSession: Bool, spotifyInstalled: Bool) -> Choice {
        if hasSession { return .mediaKey }
        if spotifyInstalled { return .resumeSpotify }
        return .mediaKey
    }
}

/// The one media-key decision. Play and pause share a key, and the key is skipped when the player is already there.
public enum MediaTransport {
    public enum Command: Equatable, Sendable { case play, pause, toggle, next, previous }
    public enum Post: Equatable, Sendable { case playPause, next, previous }

    public static func post(for command: Command, isPlaying: Bool?) -> Post? {
        switch command {
        case .play where isPlaying == true, .pause where isPlaying == false:
            return nil
        case .play, .pause, .toggle:
            return .playPause
        case .next:
            return .next
        case .previous:
            return .previous
        }
    }
}

/// Whether a local decision may run before the existing fast path.
public enum LocalCommandHook {
    public static func shouldPerform(_ decision: LocalCommandDecision, hasSession: Bool, spotifyInstalled: Bool) -> Bool {
        guard decision.consumed else { return false }
        for effect in decision.effects {
            if case .perform(.media(.play)) = effect {
                return MediaPlayPolicy.choose(hasSession: hasSession, spotifyInstalled: spotifyInstalled) != .resumeSpotify
            }
        }
        return true
    }
}

/// One finished transcript. The turn itself arms or drops a quit confirmation.
public struct LocalCommandTurn: Equatable, Sendable {
    public var machine = LocalCommandMachine()

    public init() {}

    @discardableResult
    public mutating func complete(_ transcript: String, finalAt: ContinuousClock.Instant,
                                  clock: LocalCommandClock, apps: [LocalApp]) -> LocalCommandDecision? {
        defer { machine.finishTurn() }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return machine.receive(trimmed, finalAt: finalAt, clock: clock, apps: apps)
    }
}
