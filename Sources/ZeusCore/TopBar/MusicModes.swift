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
/// and set the modes, and how to read an answer. Each answer is read from `MusicModesBox`.
/// Run the scripts only for a running player Zeus is already allowed to script. This type does not run them.
public enum MusicModeRules {
    /// Music has repeat off, all and one; Spotify's scripting interface has only repeating on or off.
    public static func supportedRepeatModes(_ player: NowPlaying.Player) -> [RepeatMode] {
        MusicModesBox.supportedRepeatModes(kind(player))
    }

    /// The mode a press moves to. Nil counts as off; a mode the player lacks goes to off.
    public static func nextRepeat(after current: RepeatMode?, player: NowPlaying.Player) -> RepeatMode {
        MusicModesBox.nextRepeat(after: current, player: kind(player))
    }

    /// One AppleScript expression: an empty string when the player is not running, otherwise shuffle and
    /// repeat joined by ASCII 31, the same character as `NowPlaying.probeSeparator`. The `is running`
    /// check comes first, so a player that quit just before the script ran is never launched again by the tell.
    public static func readScript(player: NowPlaying.Player) -> String {
        MusicModesBox.readScript(player: kind(player))
    }

    /// Reads `readScript`'s answer. Music says `true|false` and `off|one|all`; Spotify says two booleans.
    /// Nil for no answer, an empty or malformed one, or a word the player does not use. Case is ignored.
    public static func parse(_ output: String?, player: NowPlaying.Player) -> MusicModes? {
        MusicModesBox.parse(output, player: kind(player))
    }

    /// Set scripts start with the same `is not running` check as the read script: a press can sit behind a
    /// slow read, and a tell that reaches a player that quit meanwhile would launch it again.
    public static func setShuffleScript(player: NowPlaying.Player, on: Bool) -> String {
        MusicModesBox.setShuffleScript(player: kind(player), on: on)
    }

    /// `one` on Spotify turns repeating on: it has nothing finer.
    public static func setRepeatScript(player: NowPlaying.Player, mode: RepeatMode) -> String {
        MusicModesBox.setRepeatScript(player: kind(player), mode: mode)
    }

    /// Whether the modes should be read for this update: a new player or track, or modes still unknown
    /// (Automation was not confirmed yet, or was just granted). Play and pause on a known track do not.
    public static func shouldRead(previous: NowPlaying?, current: NowPlaying, modes: MusicModes) -> Bool {
        let sameTrack = previous.map {
            $0.source == current.source && $0.title == current.title && $0.artist == current.artist
        } ?? false
        return MusicModesBox.shouldRead(
            hasPrevious: previous != nil,
            sameTrack: sameTrack,
            shuffle: modes.shuffle,
            repeatMode: modes.repeatMode
        )
    }

    /// The modes after a read. An answer replaces them, an unreadable one leaves them unknown. A read that
    /// failed outright changes nothing, except right after a press: the control then holds a guess the player
    /// never confirmed, so it goes back to unknown.
    public static func resolved(output: String?, player: NowPlaying.Player, current: MusicModes, afterPress: Bool) -> MusicModes {
        MusicModesBox.resolved(output: output, player: kind(player), current: current, afterPress: afterPress)
    }

    /// What VoiceOver says for the shuffle control: unknown is told apart from off.
    public static func spokenShuffle(_ shuffle: Bool?) -> String {
        MusicModesBox.spokenShuffle(shuffle)
    }

    /// What VoiceOver says for the repeat control: unknown is told apart from off.
    public static func spokenRepeat(_ mode: RepeatMode?) -> String {
        MusicModesBox.spokenRepeat(mode)
    }

    private static func kind(_ player: NowPlaying.Player) -> MusicModesBox.Player {
        switch player {
        case .music: .music
        case .spotify: .spotify
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
