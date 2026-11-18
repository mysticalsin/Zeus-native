import Foundation

/// What's playing in one source: Music or Spotify, read from the players' own public change notifications
/// (no private frameworks, no permission needed to read), or a media element in a browser tab.
public struct NowPlaying: Equatable, Sendable {
    public enum Player: String, CaseIterable, Sendable {
        case music = "Music"
        case spotify = "Spotify"

        public var bundleID: String {
            switch self {
            case .music: "com.apple.Music"
            case .spotify: "com.spotify.client"
            }
        }

        public init?(bundleID: String) {
            switch bundleID {
            case "com.apple.Music": self = .music
            case "com.spotify.client": self = .spotify
            default: return nil
            }
        }

        /// Distributed notification each player posts when the track or state changes.
        public var notificationName: String {
            switch self {
            case .music: "com.apple.Music.playerInfo"
            case .spotify: "com.spotify.client.PlaybackStateChanged"
            }
        }
    }

    public var source: NowPlayingSource
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool
    /// Seconds, 0 when unknown.
    public var duration: Double
    public var position: Double
    public var positionAt: Date
    /// Spotify's "spotify:track:<id>" from its notification; nil for Music.
    public var trackID: String?
    /// How fast `position` advances while playing: 1 is normal speed, 0 holds it.
    public var rate: Double
    /// The cover's own link when the source names one (a browser page does); nil otherwise.
    public var artworkURL: URL?

    public init(source: NowPlayingSource, title: String, artist: String, album: String, isPlaying: Bool,
                duration: Double, position: Double, positionAt: Date = Date(), trackID: String? = nil,
                rate: Double = 1, artworkURL: URL? = nil) {
        self.trackID = trackID
        self.source = source
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.duration = duration
        self.position = position
        self.positionAt = positionAt
        self.rate = rate
        self.artworkURL = artworkURL
    }

    public init(player: Player, title: String, artist: String, album: String, isPlaying: Bool,
                duration: Double, position: Double, positionAt: Date = Date(), trackID: String? = nil) {
        self.init(source: .player(player), title: title, artist: artist, album: album, isPlaying: isPlaying,
                  duration: duration, position: position, positionAt: positionAt, trackID: trackID)
    }

    /// What this item can be asked to do: its source's base set, narrowed by what the item itself offers. A scrub
    /// needs a length. Lyrics need an artist for the lookup, and a browser item also needs a length.
    public var capabilities: SourceCapabilities {
        var result = source.baseCapabilities
        if duration <= 0 { result.remove(.seek) }
        let askable = LRCLIBQuery(self).isAskable
        let lyricsHold: Bool
        switch source {
        case .player: lyricsHold = askable
        case .browser: lyricsHold = askable && duration > 0
        }
        if !lyricsHold { result.remove(.lyrics) }
        return result
    }

    /// Returns nil for "Stopped" or a notification without a track.
    public static func parse(_ info: [AnyHashable: Any], player: Player, now: Date = Date()) -> NowPlaying? {
        let state = ((info["Player State"] as? String) ?? "").lowercased()
        guard state != "stopped", let title = info["Name"] as? String, !title.isEmpty else { return nil }
        let number: (String) -> Double? = { key in
            if let value = info[key] as? Double { return value }
            if let value = info[key] as? Int { return Double(value) }
            if let value = info[key] as? NSNumber { return value.doubleValue }
            return nil
        }
        // Music reports "Total Time" in ms; Spotify reports "Duration" in ms and position in s.
        let milliseconds: Double?
        let trackID: String?
        switch player {
        case .music:
            milliseconds = number("Total Time") ?? number("Duration")
            trackID = nil
        case .spotify:
            milliseconds = number("Duration") ?? number("Total Time")
            trackID = info["Track ID"] as? String
        }
        // Spotify sends "Playback Position"; Music's notification has no position, so a lookalike key is read if present.
        let position = number("Playback Position") ?? number("Player Position") ?? number("Elapsed") ?? 0
        return NowPlaying(player: player, title: title, artist: (info["Artist"] as? String) ?? "",
                          album: (info["Album"] as? String) ?? "", isPlaying: state == "playing",
                          duration: max((milliseconds ?? 0) / 1000, 0), position: max(position, 0), positionAt: now,
                          trackID: trackID)
    }

    /// Separator between the fields of `probeScript`'s answer (ASCII unit separator: never in a title).
    public static let probeSeparator = "\u{1F}"

    /// One AppleScript expression that answers with the player's current state, or "stopped".
    /// Run only for a running player Zeus is already allowed to script. The `is running` check comes first,
    /// so a player that quit just before the script ran is never launched again by the tell.
    public static func probeScript(player: Player) -> String {
        // Music's `duration` is seconds; Spotify's is milliseconds. `parseProbe` knows which.
        "if application id \"\(player.bundleID)\" is not running then return \"stopped\"\n"
            + "tell application id \"\(player.bundleID)\"\n"
            + "if player state is stopped then return \"stopped\"\n"
            + "set sep to (ASCII character 31)\n"
            + "set t to current track\n"
            + "return (player state as string) & sep & (name of t) & sep & (artist of t) & sep & (album of t)"
            + " & sep & (duration of t as string) & sep & (player position as string)\n"
            + "end tell"
    }

    /// Reads `probeScript`'s answer. nil for "stopped", an empty or malformed answer, or a track without a name.
    public static func parseProbe(_ output: String?, player: Player, now: Date = Date()) -> NowPlaying? {
        guard let output else { return nil }
        let fields = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: probeSeparator)
        guard fields.count >= 6 else { return nil }
        let state = fields[0].lowercased()
        let title = fields[1]
        guard state != "stopped", !title.isEmpty else { return nil }
        // AppleScript prints reals with the locale's decimal mark ("12,5").
        let number: (String) -> Double = { Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let rawDuration = number(fields[4])
        let duration: Double
        switch player {
        case .music: duration = rawDuration
        case .spotify: duration = rawDuration / 1000
        }
        return NowPlaying(player: player, title: title, artist: fields[2], album: fields[3], isPlaying: state == "playing",
                          duration: max(duration, 0), position: max(number(fields[5]), 0), positionAt: now)
    }

    public func elapsed(at now: Date = Date()) -> Double {
        let value = isPlaying ? position + now.timeIntervalSince(positionAt) * max(rate, 0) : position
        return duration > 0 ? min(max(value, 0), duration) : max(value, 0)
    }

    /// A stable hue per album so the art tile has its own colour without fetching artwork.
    public var hue: Double {
        let seed = (album.isEmpty ? title : album).unicodeScalars.reduce(UInt32(2166136261)) { ($0 ^ $1.value) &* 16777619 }
        return Double(seed % 360) / 360
    }
}

/// A meeting link found in an event's URL, location or notes.
public enum MeetingLink {
    private static let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com", "around.co"]

    /// How many wrapper layers (Safe Links, Google redirect) are peeled before giving up.
    private static let wrapperDepthLimit = 2

    private static func matches(_ host: String, _ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }

    private static func isMeetingHost(_ host: String) -> Bool { hosts.contains { matches(host, $0) } }

    /// The real URL behind a Safe Links or Google redirect wrapper; nil when `url` is not a wrapper.
    private static func unwrapped(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(), let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let keys: [String]
        if matches(host, "safelinks.protection.outlook.com") {
            keys = ["url"]
        } else if matches(host, "google.com"), url.path == "/url" {
            keys = ["q", "url"]
        } else {
            return nil
        }
        for key in keys {
            if let value = items.first(where: { $0.name == key })?.value, let inner = URL(string: value), inner.host != nil { return inner }
        }
        return nil
    }

    /// The meeting URL for `url`: itself when its host is allowed, else the unwrapped inner URL (a couple of levels at most).
    private static func meetingURL(_ url: URL) -> URL? {
        var current = url
        for _ in 0...wrapperDepthLimit {
            if let host = current.host?.lowercased(), isMeetingHost(host) { return current }
            guard let inner = unwrapped(current) else { return nil }
            current = inner
        }
        return nil
    }

    public static func find(in texts: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts.compactMap({ $0 }) {
            let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let url = match.url, let meeting = meetingURL(url) { return meeting }
            }
        }
        return nil
    }
}
