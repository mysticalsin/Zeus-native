import Foundation

/// Where a browser tab's media comes from: the tab, the page document in it, and a short fingerprint of what is
/// playing. The host is for display only and stays in memory.
public struct BrowserMediaKey: Hashable, Sendable {
    public var tabID: Int
    public var documentID: String
    public var host: String
    public var fingerprint: String

    public init(tabID: Int, documentID: String, host: String, fingerprint: String) {
        self.tabID = tabID
        self.documentID = documentID
        self.host = host
        self.fingerprint = fingerprint
    }
}

/// What a source can be asked to do. A command the source cannot honour is ignored, never sent.
public struct SourceCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let playPause = SourceCapabilities(rawValue: 1 << 0)
    public static let next = SourceCapabilities(rawValue: 1 << 1)
    public static let previous = SourceCapabilities(rawValue: 1 << 2)
    public static let seek = SourceCapabilities(rawValue: 1 << 3)
    public static let shuffle = SourceCapabilities(rawValue: 1 << 4)
    public static let repeatMode = SourceCapabilities(rawValue: 1 << 5)
    public static let lyrics = SourceCapabilities(rawValue: 1 << 6)

    /// Whether a command may go to a source with these capabilities. Open is never a capability: any source can be opened.
    public func allows(_ command: MusicCommandKind) -> Bool {
        switch command {
        case .play, .pause, .playPause: contains(.playPause)
        case .next: contains(.next)
        case .previous: contains(.previous)
        case .seek: contains(.seek)
        case .toggleShuffle: contains(.shuffle)
        case .cycleRepeat: contains(.repeatMode)
        case .open: true
        }
    }
}

/// The notch's music commands, one case each, plus an explicit `play` and `pause` for sources with no toggle
/// and `seek` for the scrubber.
public enum MusicCommandKind: Equatable, Sendable, CaseIterable {
    case play, pause, playPause, next, previous, seek, open, toggleShuffle, cycleRepeat
}

/// How a source's cover is found.
public enum ArtworkStrategy: Equatable, Sendable {
    /// Spotify's public oEmbed for the track in its notification.
    case spotifyOEmbed
    /// The iTunes Search API for the album.
    case catalogSearch
    /// The page's own image link. Never read from or written to disk.
    case pageImage
    case none
}

/// One place playback can come from: a scripted player app, or a media element in a browser tab. Every fact that
/// differs by kind is a property here; code elsewhere reads the property and does not match on the cases.
/// A new kind is one new case, and the few places that must match name every case with no `default`, so the
/// build stops there.
public enum NowPlayingSource: Hashable, Sendable {
    case player(NowPlaying.Player)
    case browser(BrowserMediaKey)
    /// This Mac's current audio, read by the local helper. It never outranks a player or a browser tab.
    case system

    /// The word the notch uses for the source.
    public var kindName: String {
        switch self {
        case .player(let player): player.rawValue
        case .browser: "Chrome"
        case .system: "This Mac"
        }
    }

    /// The app that opens when the person asks to open the source.
    public var appBundleID: String {
        switch self {
        case .player(let player): player.bundleID
        case .browser: "com.google.Chrome"
        case .system: ""
        }
    }

    /// What the source can do at best. An item narrows it (`NowPlaying.capabilities`).
    public var baseCapabilities: SourceCapabilities {
        switch self {
        case .player: [.playPause, .next, .previous, .seek, .shuffle, .repeatMode, .lyrics]
        case .browser: [.playPause, .seek, .lyrics]
        case .system: []
        }
    }

    public var artworkStrategy: ArtworkStrategy {
        switch self {
        case .player(let player):
            switch player {
            case .music: .catalogSearch
            case .spotify: .spotifyOEmbed
            }
        case .browser: .pageImage
        case .system: .none
        }
    }

    /// The player Zeus drives with Apple Events, nil for a source that is not one. Only such a source can be pinned,
    /// have its shuffle and repeat read, or be launched when it is not running.
    public var scriptedPlayer: NowPlaying.Player? {
        switch self {
        case .player(let player): player
        case .browser, .system: nil
        }
    }

    /// Whether anything derived from an item (its cover, its lyrics) may be kept on disk. A page's never is.
    public var persistsDerivedData: Bool {
        switch self {
        case .player: true
        case .browser, .system: false
        }
    }
}
