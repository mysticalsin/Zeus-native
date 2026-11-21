import Foundation

/// Which repeat modes each player offers. Repeat one stays hidden when the player has no such mode.
public struct MediaRepeatAvailability: Equatable, Sendable {
    public var playerIndex: Int
    public var modes: [RepeatMode]
    public var offersOne: Bool

    public init(playerIndex: Int, modes: [RepeatMode], offersOne: Bool) {
        self.playerIndex = playerIndex
        self.modes = modes
        self.offersOne = offersOne
    }

    public static var all: [MediaRepeatAvailability] {
        NowPlaying.Player.allCases.enumerated().map { index, player in
            let modes = MusicModeRules.supportedRepeatModes(player)
            return MediaRepeatAvailability(playerIndex: index, modes: modes, offersOne: modes.contains(.one))
        }
    }
}

/// A shuffle or repeat script. No consent, no script. A script older than 3 seconds is abandoned.
public enum MediaTransport {
    public static let timeout: TimeInterval = 3

    public static func abandoned(age: TimeInterval) -> Bool { age > timeout }

    public static func script(consent: Bool, player: NowPlaying.Player, age: TimeInterval, shuffleOn: Bool) -> String? {
        guard consent, !abandoned(age: age) else { return nil }
        return MusicModeRules.setShuffleScript(player: player, on: shuffleOn)
    }

    public static func repeatScript(consent: Bool, player: NowPlaying.Player, age: TimeInterval, mode: RepeatMode) -> String? {
        guard consent, !abandoned(age: age) else { return nil }
        let supported = MusicModeRules.supportedRepeatModes(player)
        let applied = supported.contains(mode) ? mode : .off
        return MusicModeRules.setRepeatScript(player: player, mode: applied)
    }
}

/// The left-hand player button. A control the source cannot honour is not shown.
public struct MediaLeftButtonPlan: Equatable, Sendable {
    public var symbol: String
    public var accessibilityLabel: String
    public var shown: Bool
    public var enabled: Bool

    public init(symbol: String, accessibilityLabel: String, shown: Bool, enabled: Bool) {
        self.symbol = symbol
        self.accessibilityLabel = accessibilityLabel
        self.shown = shown
        self.enabled = enabled
    }
}

public enum MediaLeftButtonRules {
    public static func plan(choice: MediaLeftButton, capabilities: SourceCapabilities, lyricsOn: Bool) -> MediaLeftButtonPlan {
        switch choice {
        case .previous:
            let shown = capabilities.contains(.previous)
            return MediaLeftButtonPlan(symbol: choice.symbol, accessibilityLabel: choice.title, shown: shown, enabled: shown)
        case .like:
            return MediaLeftButtonPlan(symbol: choice.symbol, accessibilityLabel: choice.title, shown: true, enabled: true)
        case .lyrics:
            let shown = capabilities.contains(.lyrics)
            return MediaLeftButtonPlan(symbol: choice.symbol, accessibilityLabel: choice.title, shown: shown, enabled: shown && lyricsOn)
        }
    }
}

/// Levels for the live wave. Silence is an empty state, not a row of invented peaks.
public struct MediaWaveform: Equatable, Sendable {
    public var bars: [Double]
    public var animates: Bool
    public var isSilent: Bool

    public init(bars: [Double], animates: Bool, isSilent: Bool) {
        self.bars = bars
        self.animates = animates
        self.isSilent = isSilent
    }

    public static func make(levels: [Double], enabled: Bool, reduceMotion: Bool) -> MediaWaveform? {
        guard enabled else { return nil }
        let bars = levels.map { value -> Double in
            guard value.isFinite else { return 0 }
            return min(max(value, 0), 1)
        }
        let shown = bars.isEmpty ? [0.0] : bars
        let silent = shown.allSatisfy { $0 == 0 }
        return MediaWaveform(bars: shown, animates: !reduceMotion && !silent, isSilent: silent)
    }
}

/// What the lyric line shows. A failure stays a failure and is not stored as "no lyrics".
public enum MediaLyricPhase: Equatable, Sendable {
    case ready
    case loading
    case empty
    case unavailable
}

public enum MediaLyricHighlight: Equatable, Sendable {
    case off
    case loading
    case empty
    case unavailable
    case wholeLine(String)
    case word(line: String, index: Int, count: Int)
}

public enum MediaLyricPreview {
    public static func highlight(enabled: Bool, wordByWord: Bool, phase: MediaLyricPhase, line: LyricLine, lineEnd: Double, time: Double) -> MediaLyricHighlight {
        guard enabled else { return .off }
        switch phase {
        case .loading: return .loading
        case .empty: return .empty
        case .unavailable: return .unavailable
        case .ready:
            guard wordByWord else { return .wholeLine(line.text) }
            let words = LyricWordTiming.words(in: line, lineEnd: lineEnd)
            guard let index = LyricWordTiming.index(words, at: time) else { return .wholeLine(line.text) }
            return .word(line: line.text, index: index, count: words.count)
        }
    }

    /// Empty means the service answered and had nothing. A failure must not take that path.
    public static func remembersFailureAsMissing(_ highlight: MediaLyricHighlight) -> Bool {
        if case .empty = highlight { return true }
        return false
    }
}

/// Keep-awake for music uses the rule the notch already has, including its battery and heat stops.
public enum MediaAwakePlan {
    public static func verdict(enabled: Bool, isPlaying: Bool, lastPlayedAt: Date?, now: Date,
                               power: KeepAwakeRules.Power, rules: KeepAwakeRules) -> MusicAwakeRule.Verdict {
        MusicAwakeRule().decide(enabled: enabled, isPlaying: isPlaying, lastPlayedAt: lastPlayedAt, now: now, power: power, rules: rules)
    }
}
