import Foundation

/// Which source the notch shows. One entry per source; the one that most recently started playing is shown. With
/// none playing the one that stopped last stays, paused. A source first seen paused never displaces the shown one,
/// and a track change is not a start. Pure: feeds report, the app layer shows what `shown(follow:)` says.
public struct NowPlayingArbiter: Equatable, Sendable {
    /// Which sources may be shown: any, or only one player.
    public enum Follow: Equatable, Sendable {
        case any
        case pinned(NowPlaying.Player)

        /// Every choice of the "Show music from" setting, in the order the menu lists them.
        public static let choices: [Follow] = [.any] + NowPlaying.Player.allCases.map { .pinned($0) }

        /// The words of the setting. An unknown or missing label follows any source.
        public init(label: String?) {
            self = Self.choices.first { $0.label == label } ?? .any
        }

        public var label: String {
            switch self {
            case .any: "Any player"
            case .pinned(let player): player.rawValue
            }
        }
    }

    public struct Entry: Equatable, Sendable {
        public var playing: NowPlaying
        /// When the source last went from not playing to playing; `.distantPast` if it never has.
        public var startedAt: Date
        /// The last sample that found the source playing, or the one that found it just stopped; `.distantPast` if it
        /// never played. It orders the sources when none plays.
        public var lastPlayingAt: Date
        public var seenAt: Date

        public var isPlaying: Bool { playing.isPlaying }
    }

    private var entries: [NowPlayingSource: Entry] = [:]

    public init() {}

    /// Records a sample for a source; nil removes it. A sample that belongs to another source is rejected and changes
    /// nothing. True when the sample was taken.
    @discardableResult
    public mutating func update(_ source: NowPlayingSource, _ playing: NowPlaying?, now: Date) -> Bool {
        guard let playing else {
            entries[source] = nil
            return true
        }
        guard playing.source == source else { return false }
        let before = entries[source]
        let started = playing.isPlaying && before?.isPlaying != true
        let stopped = !playing.isPlaying && before?.isPlaying == true
        entries[source] = Entry(playing: playing, startedAt: started ? now : before?.startedAt ?? .distantPast,
                                lastPlayingAt: playing.isPlaying || stopped ? now : before?.lastPlayingAt ?? .distantPast, seenAt: now)
        return true
    }

    /// A player quit, a tab closed or a feed went off.
    public mutating func remove(where matches: (NowPlayingSource) -> Bool) {
        entries = entries.filter { !matches($0.key) }
    }

    public func entry(_ source: NowPlayingSource) -> Entry? { entries[source] }

    /// Whether Music or Spotify has an entry, playing or not. A browser entry does not count.
    public var hasPlayerSession: Bool {
        entries.keys.contains { source in
            switch source {
            case .player: true
            case .browser: false
            }
        }
    }

    /// The entry to show: among those that play the latest start; with none playing, the one that played last. A source
    /// that never played comes after one that did, then the latest sample orders them.
    /// Ties go to Music, then Spotify, then a browser tab by its id.
    public func shown(follow: Follow) -> Entry? {
        let allowed = entries.filter { Self.follows(follow, $0.key) }
        let playing = allowed.filter { $0.value.isPlaying }
        let pool = playing.isEmpty ? allowed : playing
        return pool.min { Self.ranks($0, before: $1) }?.value
    }

    /// Where a command goes: the shown source, else the pinned player, else Music.
    public func commandTarget(shown: NowPlayingSource?, follow: Follow) -> NowPlayingSource {
        if let shown { return shown }
        switch follow {
        case .any: return .player(.music)
        case .pinned(let player): return .player(player)
        }
    }

    // MARK: Order

    /// A pin shows a source only when it is that player.
    private static func follows(_ follow: Follow, _ source: NowPlayingSource) -> Bool {
        switch follow {
        case .any: true
        case .pinned(let player): source.scriptedPlayer == player
        }
    }

    private static func ranks(_ a: (key: NowPlayingSource, value: Entry), before b: (key: NowPlayingSource, value: Entry)) -> Bool {
        // The pool is all playing or all not, so one entry says which order applies.
        if !a.value.isPlaying, a.value.lastPlayingAt != b.value.lastPlayingAt { return a.value.lastPlayingAt > b.value.lastPlayingAt }
        if a.value.startedAt != b.value.startedAt { return a.value.startedAt > b.value.startedAt }
        if a.value.seenAt != b.value.seenAt { return a.value.seenAt > b.value.seenAt }
        return tieOrder(a.key) < tieOrder(b.key)
    }

    /// Music, Spotify, then browser tabs by tab id and document.
    private static func tieOrder(_ source: NowPlayingSource) -> (kind: Int, tab: Int, document: String) {
        switch source {
        case .player(let player):
            switch player {
            case .music: (0, 0, "")
            case .spotify: (1, 0, "")
            }
        case .browser(let key): (2, key.tabID, key.documentID)
        }
    }
}
