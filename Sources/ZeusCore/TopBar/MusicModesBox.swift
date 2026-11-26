import Foundation

/// Shuffle and repeat for Music and Spotify: the modes each player supports, the AppleScript that
/// reads or sets them, and how an answer becomes a mode. The field separator is ASCII 31, the same
/// character as `NowPlaying.probeSeparator`. A mode the player does not support goes to off.
/// This type does not read a screen, a pointer, a clock, or a stored setting, and it does not run the script.
public enum MusicModesBox {
    /// Music or Spotify, named by application id so this box does not need `NowPlaying`.
    public enum Player: Sendable {
        case music
        case spotify

        public var bundleID: String {
            switch self {
            case .music: MusicModesBox.musicBundleID
            case .spotify: MusicModesBox.spotifyBundleID
            }
        }
    }

    /// ASCII unit separator. It is not a character a mode word uses.
    public static let separator = "\u{1F}"
    public static let musicBundleID = "com.apple.Music"
    public static let spotifyBundleID = "com.spotify.client"
    public static let musicShuffleProperty = "shuffle enabled"
    public static let musicRepeatProperty = "song repeat"
    public static let spotifyShuffleProperty = "shuffling"
    public static let spotifyRepeatProperty = "repeating"

    /// Music has repeat off, all and one. Spotify's scripting interface has only repeating on or off.
    public static func supportedRepeatModes(_ player: Player) -> [RepeatMode] {
        switch player {
        case .music: [.off, .all, .one]
        case .spotify: [.off, .all]
        }
    }

    /// The mode a press moves to. Nil counts as off. A mode the player lacks goes to off.
    public static func nextRepeat(after current: RepeatMode?, player: Player) -> RepeatMode {
        let modes = supportedRepeatModes(player)
        guard let index = modes.firstIndex(of: current ?? .off) else { return .off }
        return modes[(index + 1) % modes.count]
    }

    /// One AppleScript expression. An empty string when the player is not running, otherwise shuffle
    /// and repeat joined by `separator`. The `is running` check comes first, so a player that quit
    /// just before the script ran is never launched again by the tell. The script is not run here.
    public static func readScript(player: Player) -> String {
        let (shuffle, repeating) = properties(player)
        return "if application id \"\(player.bundleID)\" is not running then return \"\"\n"
            + "tell application id \"\(player.bundleID)\"\n"
            + "set sep to (ASCII character 31)\n"
            + "return (\(shuffle) as string) & sep & (\(repeating) as string)\n"
            + "end tell"
    }

    /// Reads `readScript`'s answer. Music says `true|false` and `off|one|all`. Spotify says two booleans.
    /// Nil for no answer, an empty or malformed one, or a word the player does not use. Case is ignored.
    public static func parse(_ output: String?, player: Player) -> MusicModes? {
        guard let output else { return nil }
        let fields = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: separator)
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

    /// Set scripts start with the same `is not running` check as the read script.
    public static func setShuffleScript(player: Player, on: Bool) -> String {
        guardedSet(player: player, property: properties(player).shuffle, value: on ? "true" : "false")
    }

    /// `one` on Spotify turns repeating on: it has nothing finer.
    public static func setRepeatScript(player: Player, mode: RepeatMode) -> String {
        let value = switch player {
        case .music: mode.rawValue
        case .spotify: mode == .off ? "false" : "true"
        }
        return guardedSet(player: player, property: properties(player).repeating, value: value)
    }

    /// Whether the modes should be read. No previous item reads. A different source, title, or artist reads.
    /// The same item reads only while shuffle or repeat is still unknown. Play and pause are not an input.
    public static func shouldRead(hasPrevious: Bool, sameTrack: Bool, shuffle: Bool?, repeatMode: RepeatMode?) -> Bool {
        if !hasPrevious || !sameTrack { return true }
        return shuffle == nil || repeatMode == nil
    }

    /// The modes after a read. An answer replaces them. An unreadable one leaves them unknown.
    /// A read that failed outright changes nothing, except right after a press: the control then holds
    /// a guess the player never confirmed, so it goes back to unknown.
    public static func resolved(output: String?, player: Player, current: MusicModes, afterPress: Bool) -> MusicModes {
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

    private static func guardedSet(player: Player, property: String, value: String) -> String {
        "if application id \"\(player.bundleID)\" is not running then return \"\"\n"
            + "tell application id \"\(player.bundleID)\"\n"
            + "set \(property) to \(value)\n"
            + "end tell"
    }

    private static func properties(_ player: Player) -> (shuffle: String, repeating: String) {
        switch player {
        case .music: (musicShuffleProperty, musicRepeatProperty)
        case .spotify: (spotifyShuffleProperty, spotifyRepeatProperty)
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
