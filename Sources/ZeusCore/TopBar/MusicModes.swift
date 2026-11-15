import Foundation

/// How a player repeats. Spotify has no `one`.
public enum RepeatMode: String, CaseIterable, Equatable, Sendable {
    case off, all, one
}

/// Shuffle and repeat as the player reports them. Nil means the player has not said
/// (no Automation consent, player not running, or an answer that could not be read).
public struct MusicModes: Equatable, Sendable {
    public var shuffle: Bool?
    public var repeatMode: RepeatMode?

    public init(shuffle: Bool? = nil, repeatMode: RepeatMode? = nil) {
        self.shuffle = shuffle
        self.repeatMode = repeatMode
    }
}

/// Pure rules for the shuffle and repeat controls: what each player supports, the scripts that read
/// and set the modes, and how to read an answer. Run the scripts only for a running player Zeus is
/// already allowed to script.
public enum MusicModeRules {
    /// Music has repeat off, all and one; Spotify's scripting interface has only repeating on or off.
    public static func supportedRepeatModes(_ player: NowPlaying.Player) -> [RepeatMode] {
        switch player {
        case .music: [.off, .all, .one]
        case .spotify: [.off, .all]
        }
    }

    /// The mode a press moves to. Nil counts as off; a mode the player lacks goes to off.
    public static func nextRepeat(after current: RepeatMode?, player: NowPlaying.Player) -> RepeatMode {
        let modes = supportedRepeatModes(player)
        guard let index = modes.firstIndex(of: current ?? .off) else { return .off }
        return modes[(index + 1) % modes.count]
    }

    /// One AppleScript expression: an empty string when the player is not running, otherwise shuffle and
    /// repeat joined by `NowPlaying.probeSeparator`. The `is running` check comes first, so a player that
    /// quit just before the script ran is never launched again by the tell.
    public static func readScript(player: NowPlaying.Player) -> String {
        let (shuffle, repeating) = properties(player)
        return "if application id \"\(player.bundleID)\" is not running then return \"\"\n"
            + "tell application id \"\(player.bundleID)\"\n"
            + "set sep to (ASCII character 31)\n"
            + "return (\(shuffle) as string) & sep & (\(repeating) as string)\n"
            + "end tell"
    }

    /// Reads `readScript`'s answer. Music says `true|false` and `off|one|all`; Spotify says two booleans.
    /// Nil for no answer, an empty or malformed one, or a word the player does not use. Case is ignored.
    public static func parse(_ output: String?, player: NowPlaying.Player) -> MusicModes? {
        guard let output else { return nil }
        let fields = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: NowPlaying.probeSeparator)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard fields.count == 2, let shuffle = bool(fields[0]) else { return nil }
        let mode: RepeatMode?
        switch player {
        case .music: mode = RepeatMode(rawValue: fields[1])
        case .spotify: mode = bool(fields[1]).map { $0 ? .all : .off }
        }
        guard let mode else { return nil }
        return MusicModes(shuffle: shuffle, repeatMode: mode)
    }

    /// Set scripts start with the same `is not running` check as the read script: a press can sit behind a
    /// slow read, and a tell that reaches a player that quit meanwhile would launch it again.
    public static func setShuffleScript(player: NowPlaying.Player, on: Bool) -> String {
        guardedSet(player: player, property: properties(player).shuffle, value: "\(on)")
    }

    /// `one` on Spotify turns repeating on: it has nothing finer.
    public static func setRepeatScript(player: NowPlaying.Player, mode: RepeatMode) -> String {
        let value = switch player {
        case .music: mode.rawValue
        case .spotify: mode == .off ? "false" : "true"
        }
        return guardedSet(player: player, property: properties(player).repeating, value: value)
    }

    /// Whether the modes should be read for this update: a new player or track, or modes still unknown
    /// (Automation was not confirmed yet, or was just granted). Play and pause on a known track do not.
    public static func shouldRead(previous: NowPlaying?, current: NowPlaying, modes: MusicModes) -> Bool {
        guard let previous else { return true }
        if previous.source != current.source || previous.title != current.title || previous.artist != current.artist {
            return true
        }
        return modes.shuffle == nil || modes.repeatMode == nil
    }

    /// The modes after a read. An answer replaces them, an unreadable one leaves them unknown. A read that
    /// failed outright changes nothing, except right after a press: the control then holds a guess the player
    /// never confirmed, so it goes back to unknown.
    public static func resolved(output: String?, player: NowPlaying.Player, current: MusicModes, afterPress: Bool) -> MusicModes {
        guard let output else { return afterPress ? MusicModes() : current }
        return parse(output, player: player) ?? MusicModes()
    }

    /// What VoiceOver says for the shuffle control: unknown is told apart from off.
    public static func spokenShuffle(_ shuffle: Bool?) -> String {
        shuffle.map { $0 ? "on" : "off" } ?? "unknown"
    }

    /// What VoiceOver says for the repeat control: unknown is told apart from off.
    public static func spokenRepeat(_ mode: RepeatMode?) -> String {
        mode?.rawValue ?? "unknown"
    }

    private static func guardedSet(player: NowPlaying.Player, property: String, value: String) -> String {
        "if application id \"\(player.bundleID)\" is not running then return \"\"\n"
            + "tell application id \"\(player.bundleID)\"\n"
            + "set \(property) to \(value)\n"
            + "end tell"
    }

    /// The scripting dictionary's names for shuffle and repeat.
    private static func properties(_ player: NowPlaying.Player) -> (shuffle: String, repeating: String) {
        switch player {
        case .music: ("shuffle enabled", "song repeat")
        case .spotify: ("shuffling", "repeating")
        }
    }

    private static func bool(_ word: String) -> Bool? {
        switch word {
        case "true": true
        case "false": false
        default: nil
        }
    }
}

/// One press of the shuffle or repeat control as a pure state machine, so the order of its steps is tested
/// and the app layer only carries out each effect and reports what happened.
///
/// A known mode moves at once and its change is sent; an unknown mode is read from the player first and the
/// change is computed from that answer. Without an answer nothing is sent: a set built from a guess could
/// undo what the person asked for. After a send the player is read back; an answer that has been overtaken
/// by a newer press or read is dropped.
public struct MusicModePress: Equatable, Sendable {
    public enum Control: Equatable, Sendable {
        case shuffle, repeatMode
    }

    public enum Phase: Equatable, Sendable {
        case idle, readingFirst, sending, readingBack, finished
    }

    /// What happened since the last effect.
    public enum Event: Equatable, Sendable {
        /// The player's modes, read directly before the send; nil when the read failed or could not be parsed.
        case playerRead(MusicModes?)
        /// The set script ran.
        case sent
        /// The read after the send. `current` is what the control shows now; `isCurrent` is false when a
        /// newer press, read or reset has taken over since this read began.
        case readBack(output: String?, current: MusicModes, isCurrent: Bool)
        /// The player quit or lost consent.
        case unavailable
    }

    /// What the app layer does next.
    public enum Effect: Equatable, Sendable {
        /// Read shuffle and repeat from the player, ignoring the shared read revision.
        case readPlayer
        case send(script: String)
        case readBack
        /// Put these modes on the control and end the press.
        case show(MusicModes)
        case stop
    }

    public let control: Control
    public let player: NowPlaying.Player
    public private(set) var phase: Phase = .idle
    private var base = MusicModes()

    public init(control: Control, player: NowPlaying.Player) {
        self.control = control
        self.player = player
    }

    /// The press itself. `optimistic` is what the control shows at once (nil while the mode is unknown);
    /// `next` is the first effect. A press that already started does nothing.
    public mutating func press(current: MusicModes) -> (optimistic: MusicModes?, next: Effect) {
        guard phase == .idle else { return (nil, .stop) }
        base = current
        if let script = script(from: current) {
            phase = .sending
            var shown = current
            switch control {
            case .shuffle: shown.shuffle = current.shuffle.map { !$0 }
            case .repeatMode: shown.repeatMode = MusicModeRules.nextRepeat(after: current.repeatMode, player: player)
            }
            return (shown, .send(script: script))
        }
        phase = .readingFirst
        return (nil, .readPlayer)
    }

    /// Moves on after an effect. An event that does not belong to the current step ends the press.
    public mutating func handle(_ event: Event) -> Effect {
        switch (phase, event) {
        case (.readingFirst, .playerRead(let read)):
            guard let read, let script = script(from: read) else { return finish(.stop) }
            base = read
            phase = .sending
            return .send(script: script)
        case (.sending, .sent):
            phase = .readingBack
            return .readBack
        case (.readingBack, .readBack(let output, let current, let isCurrent)):
            guard isCurrent else { return finish(.stop) }
            return finish(.show(MusicModeRules.resolved(output: output, player: player, current: current, afterPress: true)))
        case (.readingBack, .unavailable):
            // The control holds a guess the player never confirmed.
            return finish(.show(MusicModes()))
        default:
            return finish(.stop)
        }
    }

    private mutating func finish(_ effect: Effect) -> Effect {
        phase = .finished
        return effect
    }

    /// The set script for these modes, or nil when the mode this control changes is unknown.
    private func script(from modes: MusicModes) -> String? {
        switch control {
        case .shuffle:
            guard let on = modes.shuffle else { return nil }
            return MusicModeRules.setShuffleScript(player: player, on: !on)
        case .repeatMode:
            guard let mode = modes.repeatMode else { return nil }
            return MusicModeRules.setRepeatScript(player: player, mode: MusicModeRules.nextRepeat(after: mode, player: player))
        }
    }
}

/// How a toggle that is on is drawn: a filled capsule with a border, so the state rests on shape and
/// contrast, not on a tint alone. Off has neither. The glyph takes the primary tone when on.
public enum ToggleOnLook {
    /// White over the panel. At 0.30 the primary glyph (E9EDF2) keeps text-grade contrast on the capsule.
    public static let fillOpacity = 0.30
    /// The border, strong enough to separate the capsule from the dark panel.
    public static let strokeOpacity = 0.50

    public static func fill(active: Bool) -> Double { active ? fillOpacity : 0 }
    public static func stroke(active: Bool) -> Double { active ? strokeOpacity : 0 }

    /// What VoiceOver says for a plain on or off toggle.
    public static func spoken(_ on: Bool) -> String { on ? "on" : "off" }
}
