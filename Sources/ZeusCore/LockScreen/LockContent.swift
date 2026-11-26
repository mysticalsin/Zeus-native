import Foundation

/// What a locked Mac may show. A value, so the view and the controller never decide what is revealed.
/// No window, no player, and no session read live here.

/// Music or Spotify is a desktop player. Anything else, including a browser tab, is `other`.
public enum LockTrackKind: Equatable, Sendable {
    case player
    case other
}

/// One track, copied into fields this file owns. It does not use the app's now-playing type.
public struct LockTrack: Equatable, Sendable {
    public var kind: LockTrackKind
    public var playerRunning: Bool
    public var title: String
    public var artist: String
    public var hue: Double
    public var isPlaying: Bool
    /// Seconds, 0 when the player did not say.
    public var duration: Double
    public var position: Double
    /// When `position` was read. While playing, elapsed time moves from here at normal speed.
    public var positionAt: Date
    /// True only when Zeus may already send play, pause, next, and previous. A press never asks.
    public var canControl: Bool

    public init(kind: LockTrackKind, playerRunning: Bool, title: String, artist: String, hue: Double,
                isPlaying: Bool, duration: Double, position: Double, positionAt: Date, canControl: Bool) {
        self.kind = kind
        self.playerRunning = playerRunning
        self.title = title
        self.artist = artist
        self.hue = hue
        self.isPlaying = isPlaying
        self.duration = duration
        self.position = position
        self.positionAt = positionAt
        self.canControl = canControl
    }

    /// Seconds into the track at `now`. A pause holds `position`. A playing track advances at normal speed
    /// and never runs past a known duration.
    public func elapsed(at now: Date) -> Double {
        let advanced = isPlaying ? position + now.timeIntervalSince(positionAt) : position
        guard advanced.isFinite else { return 0 }
        let started = max(advanced, 0)
        guard duration.isFinite, duration > 0 else { return started }
        return min(started, duration)
    }
}

/// The switches that change the lock screen. `hideDetails` is on when track details are private or a meeting
/// is hiding them. `lyrics` and `lyricsPrivacy` must both be on before a line is shown.
public struct LockOptions: Equatable, Sendable {
    public var showTrackDetails: Bool
    public var hideDetails: Bool
    public var lyrics: Bool
    public var lyricsPrivacy: Bool
    public var clock: Bool

    public init(showTrackDetails: Bool, hideDetails: Bool, lyrics: Bool, lyricsPrivacy: Bool, clock: Bool) {
        self.showTrackDetails = showTrackDetails
        self.hideDetails = hideDetails
        self.lyrics = lyrics
        self.lyricsPrivacy = lyricsPrivacy
        self.clock = clock
    }

    public static let open = LockOptions(showTrackDetails: true, hideDetails: false, lyrics: true,
                                         lyricsPrivacy: true, clock: true)
}

/// Previous, play or pause, and next. A control that is absent is not drawn, and nothing else exists to send.
public struct LockControls: OptionSet, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let previous = LockControls(rawValue: 1 << 0)
    public static let playPause = LockControls(rawValue: 1 << 1)
    public static let next = LockControls(rawValue: 1 << 2)
    public static let transport: LockControls = [.previous, .playPause, .next]
}

/// Elapsed and duration in seconds. The words a row shows come from `times`.
public struct LockProgress: Equatable, Sendable {
    public var elapsed: Double
    public var duration: Double

    public init(elapsed: Double, duration: Double) {
        self.elapsed = elapsed
        self.duration = duration
    }

    /// `m:ss`, or `h:mm:ss` once the count reaches an hour. Remaining is never negative.
    public static func times(elapsed: Double, duration: Double) -> (elapsed: String, remaining: String) {
        let played = finiteSeconds(elapsed)
        let length = finiteSeconds(duration)
        return (clock(played), clock(max(length - played, 0)))
    }

    private static func finiteSeconds(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(value, 0)
    }

    private static func clock(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded(.down))
        let sec = whole % 60
        let min = (whole / 60) % 60
        let hour = whole / 3600
        if hour > 0 { return String(format: "%d:%02d:%02d", hour, min, sec) }
        return String(format: "%d:%02d", whole / 60, sec)
    }
}

/// The full card keeps the names. The quiet card keeps play state and the buttons, and nothing that names the track.
public enum LockCard: Equatable, Sendable {
    case full(title: String, artist: String, hue: Double, isPlaying: Bool, progress: LockProgress, lyric: String?,
              controls: LockControls)
    case quiet(isPlaying: Bool, controls: LockControls)

    public var isPlaying: Bool {
        switch self {
        case .full(_, _, _, let isPlaying, _, _, _): isPlaying
        case .quiet(let isPlaying, _): isPlaying
        }
    }

    public var controls: LockControls {
        switch self {
        case .full(_, _, _, _, _, _, let controls): controls
        case .quiet(_, let controls): controls
        }
    }
}

/// One look at the lock screen: a card, a clock row, both, or nothing.
public struct LockScene: Equatable, Sendable {
    public var card: LockCard?
    public var showsClock: Bool
    /// True when there is nothing to put on screen, so no window is made.
    public var isEmpty: Bool

    public init(card: LockCard?, showsClock: Bool, isEmpty: Bool) {
        self.card = card
        self.showsClock = showsClock
        self.isEmpty = isEmpty
    }
}

/// One timed lyric line. Plain and unsynced lyrics never become one of these.
public struct LockLyricLine: Equatable, Sendable {
    public var time: Double
    public var text: String

    public init(time: Double, text: String) {
        self.time = time
        self.text = text
    }
}

/// What a lyric lookup returned. Only `.synced` can put words on the lock screen.
public enum LockLyrics: Equatable, Sendable {
    case synced([LockLyricLine])
    case plain(String)
    case instrumental
    case none
}

public enum LockText {
    public static let titleLimit = 80
    public static let artistLimit = 60
    public static let lyricLimit = 120

    /// Drops controls, line breaks, zero-width characters, and direction overrides, collapses spaces,
    /// and cuts at `limit`. Empty after that is absent.
    public static func clean(_ text: String, limit: Int) -> String? {
        var kept = ""
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            // A joiner sits inside one extended grapheme, so the scan is by scalar. Dropping the
            // whole grapheme would also drop the letters on either side.
            if isLineBreak(scalar) || isHiddenMark(scalar) { continue }
            if scalar.properties.isWhitespace {
                pendingSpace = !kept.isEmpty
                continue
            }
            if isControl(scalar) { continue }
            if pendingSpace { kept.append(" ") }
            pendingSpace = false
            kept.unicodeScalars.append(scalar)
        }
        guard limit > 0 else { return nil }
        if kept.count > limit {
            kept = String(kept.prefix(limit)).trimmingCharacters(in: .whitespaces)
        }
        return kept.isEmpty ? nil : kept
    }

    private static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\n" || scalar == "\r" || scalar == "\u{2028}" || scalar == "\u{2029}" || scalar == "\u{0085}"
    }

    private static func isHiddenMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200B, 0x200C, 0x200D, 0xFEFF, 0x2060, 0x180E,
             0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
             0x2066, 0x2067, 0x2068, 0x2069:
            true
        default:
            false
        }
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || scalar.value == 0x7F
    }
}

public enum LockLyric {
    /// The synced line being sung at `elapsed`, cleaned. Plain, instrumental, and unsynced text give nil.
    /// The line is chosen the same way as a timed lyric list: the last line whose start has been reached.
    public static func line(_ lyrics: LockLyrics?, elapsed: Double) -> String? {
        guard let lyrics, case .synced(let lines) = lyrics, elapsed.isFinite else { return nil }
        guard let chosen = currentLine(lines, at: elapsed) else { return nil }
        return LockText.clean(chosen.text, limit: LockText.lyricLimit)
    }

    /// The last finite line whose start is at or before `time`. Lines are ordered by time, then by
    /// the order they were given, matching a synced lyric list.
    private static func currentLine(_ lines: [LockLyricLine], at time: Double) -> LockLyricLine? {
        let ordered = lines.enumerated().filter { $0.element.time.isFinite }.sorted { lhs, rhs in
            (lhs.element.time, lhs.offset) < (rhs.element.time, rhs.offset)
        }.map(\.element)
        guard let first = ordered.first, time >= first.time else { return nil }
        var low = 0
        var high = ordered.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if ordered[mid].time <= time { low = mid } else { high = mid - 1 }
        }
        return ordered[low]
    }
}

public enum LockContentPolicy {
    /// Full card, quiet card, or no card, plus the clock row. An unrecognised track draws nothing.
    /// A quiet card is not drawn when it would have no buttons.
    public static func scene(track: LockTrack?, options: LockOptions, lyricLine: LockLyrics?,
                              at now: Date = Date()) -> LockScene {
        let card = card(track: track, options: options, lyricLine: lyricLine, at: now)
        return LockScene(card: card, showsClock: options.clock, isEmpty: card == nil && !options.clock)
    }

    private static func card(track: LockTrack?, options: LockOptions, lyricLine: LockLyrics?,
                             at now: Date) -> LockCard? {
        guard let track, track.kind == .player, track.playerRunning else { return nil }
        let controls: LockControls = track.canControl ? .transport : []
        let reveal = options.showTrackDetails && !options.hideDetails
        if !reveal {
            guard !controls.isEmpty else { return nil }
            return .quiet(isPlaying: track.isPlaying, controls: controls)
        }
        let title = LockText.clean(track.title, limit: LockText.titleLimit) ?? ""
        let artist = LockText.clean(track.artist, limit: LockText.artistLimit) ?? ""
        if !track.isPlaying && title.isEmpty && artist.isEmpty { return nil }
        let elapsed = track.elapsed(at: now)
        let duration = track.duration.isFinite && track.duration > 0 ? track.duration : 0
        let lyric = (options.lyrics && options.lyricsPrivacy) ? LockLyric.line(lyricLine, elapsed: elapsed) : nil
        let hue = track.hue.isFinite ? track.hue : 0
        return .full(title: title, artist: artist, hue: hue, isPlaying: track.isPlaying,
                     progress: LockProgress(elapsed: elapsed, duration: duration), lyric: lyric, controls: controls)
    }
}

/// Play or pause, next, and previous. There is no other command.
public enum LockCommand: Equatable, Sendable {
    case playPause
    case next
    case previous
}

public enum LockCommandPolicy {
    /// Allowed only when that button is on the card and the session may show the surface.
    public static func allows(_ command: LockCommand, scene: LockScene, mayShow: Bool) -> Bool {
        guard mayShow, let card = scene.card else { return false }
        switch command {
        case .playPause: return card.controls.contains(.playPause)
        case .next: return card.controls.contains(.next)
        case .previous: return card.controls.contains(.previous)
        }
    }
}

public enum LockClock {
    /// The locale's hour cycle: `15:04` or `3:04 PM`. No dash characters.
    public static func time(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let format = DateFormatter()
        format.calendar = calendar
        format.locale = locale
        format.timeZone = calendar.timeZone
        format.dateFormat = uses24Hour(locale) ? "HH:mm" : "h:mm a"
        return withoutDashes(format.string(from: date))
    }

    /// The locale's weekday and date, without a dash character.
    public static func day(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let format = DateFormatter()
        format.calendar = calendar
        format.locale = locale
        format.timeZone = calendar.timeZone
        format.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return withoutDashes(format.string(from: date))
    }

    private static func uses24Hour(_ locale: Locale) -> Bool {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        return !template.contains("a")
    }

    private static func withoutDashes(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2014}", with: ", ")
            .replacingOccurrences(of: "\u{2013}", with: ", ")
    }
}

public enum LockSpoken {
    /// "Playing", "Paused", or "Title, Artist, paused". A player name is not part of the card, so it is never spoken.
    public static func card(_ scene: LockScene) -> String {
        guard let card = scene.card else { return "" }
        switch card {
        case .quiet(let isPlaying, _):
            return isPlaying ? "Playing" : "Paused"
        case .full(let title, let artist, _, let isPlaying, _, _, _):
            if isPlaying { return "Playing" }
            let names = [title, artist].filter { !$0.isEmpty }
            guard !names.isEmpty else { return "Paused" }
            return names.joined(separator: ", ") + ", paused"
        }
    }
}
