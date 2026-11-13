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
        if previous.player != current.player || previous.title != current.title || previous.artist != current.artist {
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
