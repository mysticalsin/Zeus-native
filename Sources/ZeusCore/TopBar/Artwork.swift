import Foundation

/// Where album art comes from, with no key and no permission: Spotify's public oEmbed for the track
/// in its notification, and the iTunes Search API for Apple Music. Pure URL building and parsing;
/// the app does the fetching and the disk cache (`ArtworkStore`).
public enum ArtworkSource {
    /// "spotify:track:6rqhFgbbKwnb9MLmUQDhG6" -> the bare id. Anything else (episodes, local files) is nil.
    public static func spotifyTrackID(_ uri: String?) -> String? {
        guard let uri else { return nil }
        let parts = uri.split(separator: ":").map(String.init)
        if parts.count == 3, parts[0] == "spotify", parts[1] == "track", isBase62(parts[2]) { return parts[2] }
        if let url = URL(string: uri), url.host == "open.spotify.com" {
            let path = url.pathComponents.filter { $0 != "/" }
            if path.count >= 2, path[path.count - 2] == "track", isBase62(path[path.count - 1]) { return path[path.count - 1] }
        }
        return nil
    }

    private static func isBase62(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 32 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    public static func spotifyTrackURL(trackID: String) -> URL? {
        URL(string: "https://open.spotify.com/track/\(trackID)")
    }

    /// `https://open.spotify.com/oembed?url=<track url>`
    public static func spotifyOEmbedURL(trackID: String) -> URL? {
        guard let track = spotifyTrackURL(trackID: trackID) else { return nil }
        var parts = URLComponents(string: "https://open.spotify.com/oembed")
        parts?.queryItems = [URLQueryItem(name: "url", value: track.absoluteString)]
        return parts?.url
    }

    /// `thumbnail_url` from an oEmbed answer (https only).
    public static func parseOEmbed(_ data: Data) -> URL? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = object["thumbnail_url"] as? String, let url = URL(string: text), url.scheme == "https" else { return nil }
        return url
    }

    /// Spotify's cover CDN serves 300 px ("...00001e02...") and 640 px ("...0000b273...") of one image.
    public static func spotifyFullSize(_ url: URL) -> URL {
        let text = url.absoluteString
        guard text.contains("ab67616d00001e02") else { return url }
        return URL(string: text.replacingOccurrences(of: "ab67616d00001e02", with: "ab67616d0000b273")) ?? url
    }

    /// `https://itunes.apple.com/search?term=<artist album>&entity=album&limit=1`
    public static func iTunesSearchURL(artist: String, album: String, title: String = "") -> URL? {
        let words = [artist, album.isEmpty ? title : album].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        var parts = URLComponents(string: "https://itunes.apple.com/search")
        parts?.queryItems = [
            URLQueryItem(name: "term", value: words.joined(separator: " ")),
            URLQueryItem(name: "entity", value: album.isEmpty ? "song" : "album"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        return parts?.url
    }

    /// The first result's `artworkUrl100`, upscaled (the CDN takes any size in the file name).
    public static func parseITunes(_ data: Data, size: Int = 600) -> URL? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let results = object["results"] as? [[String: Any]],
              let text = results.compactMap({ $0["artworkUrl100"] as? String }).first, let url = URL(string: text),
              url.scheme == "https" else { return nil }
        return upscale(url, to: size)
    }

    /// ".../100x100bb.jpg" becomes ".../600x600bb.jpg".
    public static func upscale(_ url: URL, to size: Int) -> URL {
        let text = url.absoluteString
        guard let range = text.range(of: #"\d{2,4}x\d{2,4}(bb)?(?=\.\w+$)"#, options: .regularExpression) else { return url }
        let tail = text[range].hasSuffix("bb") ? "bb" : ""
        return URL(string: text.replacingCharacters(in: range, with: "\(size)x\(size)\(tail)")) ?? url
    }

    /// One file name per cover: the Spotify track id, or a hash of artist and album (an album's
    /// tracks share one cover). Stable across launches.
    public static func cacheKey(for playing: NowPlaying) -> String {
        if let id = spotifyTrackID(playing.trackID) { return "spotify-" + id }
        let album = playing.album.isEmpty ? playing.title : playing.album
        return "\(playing.player == .music ? "music" : "spotify")-" + fnv(normalize(playing.artist) + "|" + normalize(album))
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fnv(_ text: String) -> String {
        let hash = text.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return String(hash, radix: 16)
    }
}

/// The artwork folder's size limit: oldest-used covers go first.
public enum ArtworkCachePolicy {
    public static let limitBytes = 50_000_000

    public struct Entry: Equatable, Sendable {
        public var name: String
        public var bytes: Int
        public var lastUsed: Date
        public init(name: String, bytes: Int, lastUsed: Date) {
            self.name = name
            self.bytes = bytes
            self.lastUsed = lastUsed
        }
    }

    /// Names to delete so what is left fits in `limit`, least recently used first.
    public static func evictions(_ entries: [Entry], limit: Int = limitBytes) -> [String] {
        var total = entries.reduce(0) { $0 + $1.bytes }
        guard total > limit else { return [] }
        var doomed: [String] = []
        for entry in entries.sorted(by: { $0.lastUsed < $1.lastUsed }) where total > limit {
            doomed.append(entry.name)
            total -= entry.bytes
        }
        return doomed
    }
}

/// The colour a cover lends the music light: its average, nudged toward a vivid tone so a dark or
/// grey cover still glows.
public enum ArtworkColor {
    public struct RGB: Equatable, Sendable {
        public var red: Double, green: Double, blue: Double
        public init(red: Double, green: Double, blue: Double) { self.red = red; self.green = green; self.blue = blue }
    }

    /// `rgba` is 8-bit RGBA pixels, row after row. Transparent pixels are ignored. nil when empty.
    public static func average(rgba: [UInt8]) -> RGB? {
        var r = 0.0, g = 0.0, b = 0.0, weight = 0.0
        var index = 0
        while index + 3 < rgba.count {
            let alpha = Double(rgba[index + 3]) / 255
            if alpha > 0.05 {
                r += Double(rgba[index]) / 255 * alpha
                g += Double(rgba[index + 1]) / 255 * alpha
                b += Double(rgba[index + 2]) / 255 * alpha
                weight += alpha
            }
            index += 4
        }
        guard weight > 0 else { return nil }
        return RGB(red: r / weight, green: g / weight, blue: b / weight)
    }

    /// Lifts saturation and brightness into a range that reads as light on black.
    public static func glow(_ color: RGB) -> RGB {
        let high = max(color.red, color.green, color.blue), low = min(color.red, color.green, color.blue)
        let saturation = high > 0 ? (high - low) / high : 0
        let boost = max(0.0, 0.55 - saturation) * 0.9
        let lift = high < 0.65 ? 0.65 / max(high, 0.05) : 1
        func tune(_ value: Double) -> Double {
            let pushed = low + (value - low) * (1 + boost)
            return min(max(pushed * lift, 0), 1)
        }
        return RGB(red: tune(color.red), green: tune(color.green), blue: tune(color.blue))
    }
}
