import Foundation

/// What's playing in Music or Spotify, read from the players' own public change notifications
/// (no private frameworks, no permission needed to read).
public struct NowPlaying: Equatable, Sendable {
    public enum Player: String, Sendable {
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

    public var player: Player
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

    public init(player: Player, title: String, artist: String, album: String, isPlaying: Bool,
                duration: Double, position: Double, positionAt: Date = Date(), trackID: String? = nil) {
        self.trackID = trackID
        self.player = player
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.duration = duration
        self.position = position
        self.positionAt = positionAt
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
        let milliseconds = player == .music ? (number("Total Time") ?? number("Duration")) : (number("Duration") ?? number("Total Time"))
        // Spotify sends "Playback Position"; Music's notification has no position, so a lookalike key is read if present.
        let position = number("Playback Position") ?? number("Player Position") ?? number("Elapsed") ?? 0
        return NowPlaying(player: player, title: title, artist: (info["Artist"] as? String) ?? "",
                          album: (info["Album"] as? String) ?? "", isPlaying: state == "playing",
                          duration: max((milliseconds ?? 0) / 1000, 0), position: max(position, 0), positionAt: now,
                          trackID: player == .spotify ? (info["Track ID"] as? String) : nil)
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
        let duration = player == .spotify ? rawDuration / 1000 : rawDuration
        return NowPlaying(player: player, title: title, artist: fields[2], album: fields[3], isPlaying: state == "playing",
                          duration: max(duration, 0), position: max(number(fields[5]), 0), positionAt: now)
    }

    public func elapsed(at now: Date = Date()) -> Double {
        let value = isPlaying ? position + now.timeIntervalSince(positionAt) : position
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

    public static func find(in texts: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts.compactMap({ $0 }) {
            let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let url = match.url, let host = url.host?.lowercased(), hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                    return url
                }
            }
        }
        return nil
    }
}
