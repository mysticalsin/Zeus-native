import Foundation

/// What the notch says about the source of the music it shows, and which controls it draws for it. Pure: the views
/// read these answers and decide nothing. A fact that differs by kind is read from the source's own properties where
/// it can be; the few answers that must match (the glyph, the line that names the source) name every case with no
/// `default`, so a new kind of source stops the build here.
public enum NowPlayingDisplay {
    /// The controls the Music page and the Home widget may draw. A control the source cannot honour is not drawn,
    /// and nothing is drawn disabled.
    public struct Controls: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let previous = Controls(rawValue: 1 << 0)
        public static let playPause = Controls(rawValue: 1 << 1)
        public static let next = Controls(rawValue: 1 << 2)
        public static let shuffle = Controls(rawValue: 1 << 3)
        public static let repeatMode = Controls(rawValue: 1 << 4)
        /// Dragging the progress line to seek. The line itself shows whenever something plays.
        public static let scrub = Controls(rawValue: 1 << 5)
        public static let lyrics = Controls(rawValue: 1 << 6)
        public static let open = Controls(rawValue: 1 << 7)
    }

    /// The separator the notch puts between two facts on one line.
    private static let separator = " \u{00B7} "

    /// The line above the title: "Music", "Spotify", or "Chrome · example.com". An empty host shows the kind alone.
    public static func sourceLine(_ source: NowPlayingSource) -> String {
        switch source {
        case .player: source.kindName
        case .browser(let key): host(key).map { source.kindName + separator + $0 } ?? source.kindName
        case .system: source.kindName
        }
    }

    /// The glyph for a source: the art tile's placeholder and the track cue's icon.
    public static func glyph(for source: NowPlayingSource) -> String {
        switch source {
        case .player(let player):
            switch player {
            case .music: "music.note"
            case .spotify: "dot.radiowaves.left.and.right"
            }
        case .browser: "globe"
        case .system: "music.note"
        }
    }

    /// The track cue's icon: the source's glyph, the note when the cue names no source.
    public static func cueGlyph(for source: NowPlayingSource?) -> String {
        source.map(glyph(for:)) ?? "music.note"
    }

    /// The Open button's label, "Open Spotify".
    public static func openLabel(for source: NowPlayingSource) -> String {
        "Open " + source.kindName
    }

    /// The controls to draw for what is shown. With nothing playing the set is today's, and fails closed to it:
    /// whatever the notch cannot tell, it draws what it always drew. The scrub is left out there, as there is no
    /// progress line to drag.
    public static func visibleControls(for item: NowPlaying?) -> Controls {
        guard let item else { return [.previous, .playPause, .next, .shuffle, .repeatMode, .lyrics, .open] }
        let capabilities = item.capabilities
        var controls: Controls = [.open]
        if capabilities.contains(.previous) { controls.insert(.previous) }
        if capabilities.contains(.playPause) { controls.insert(.playPause) }
        if capabilities.contains(.next) { controls.insert(.next) }
        if capabilities.contains(.shuffle) { controls.insert(.shuffle) }
        if capabilities.contains(.repeatMode) { controls.insert(.repeatMode) }
        if capabilities.contains(.seek) { controls.insert(.scrub) }
        if capabilities.contains(.lyrics) { controls.insert(.lyrics) }
        return controls
    }

    /// What VoiceOver reads for the left wing of the closed notch: "Playing in Spotify: Title".
    public static func accessibilityLabel(for item: NowPlaying) -> String {
        let place: String
        switch item.source {
        case .player: place = item.source.kindName
        case .browser(let key): place = host(key).map { item.source.kindName + ", " + $0 } ?? item.source.kindName
        case .system: place = item.source.kindName
        }
        return (item.isPlaying ? "Playing in " : "Paused in ") + place + ": " + item.title
    }

    /// The right wing's text for a track cue. When the shown source just changed it names the source first
    /// ("Spotify · Title"); within one source it keeps "Title · Artist". A cue with no source reads the old way.
    public static func cueText(title: String, artist: String, source: NowPlayingSource?, sourceChanged: Bool) -> String {
        if sourceChanged, let source { return source.kindName + separator + title }
        return artist.isEmpty ? title : title + separator + artist
    }

    /// Whether the cue should name the source: it is not the one the notch showed before. Two tabs on one host, or two
    /// tracks in one tab, are the same source to the person reading the notch.
    public static func sourceChanged(from previous: NowPlayingSource?, to current: NowPlayingSource) -> Bool {
        guard let previous else { return true }
        return sourceLine(previous) != sourceLine(current)
    }

    private static func host(_ key: BrowserMediaKey) -> String? {
        let trimmed = key.host.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
