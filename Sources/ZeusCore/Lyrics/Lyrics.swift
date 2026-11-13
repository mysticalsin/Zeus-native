import CryptoKit
import Foundation

/// One line of a time-synced lyric: the second it starts and what is sung.
public struct LyricLine: Equatable, Codable, Sendable {
    public var time: Double
    public var text: String
    public init(time: Double, text: String) { self.time = time; self.text = text }
}

/// What LRCLIB knew about a track.
public enum LyricsResult: Equatable, Sendable {
    case synced([LyricLine])
    case plain(String)
    case instrumental
    case none
}

/// The `.lrc` format: `[mm:ss.xx] text`, several stamps per line, an optional `[offset:+ms]` tag.
public enum LRC {
    public static func parse(_ text: String) -> [LyricLine] {
        var offset = 0.0
        var lines: [LyricLine] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw).trimmingCharacters(in: .whitespaces)[...]
            var stamps: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = String(rest[rest.index(after: rest.startIndex)..<close])
                rest = rest[rest.index(after: close)...]
                if let seconds = stamp(tag) {
                    stamps.append(seconds)
                } else if tag.lowercased().hasPrefix("offset:"), let ms = Double(tag.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
                    offset = ms / 1000
                } // other metadata tags (ar, ti, al, by...) are ignored
            }
            let words = strippingWordTags(rest).trimmingCharacters(in: .whitespaces)
            for time in stamps { lines.append(LyricLine(time: time, text: words)) }
        }
        // A positive offset makes the lyrics appear sooner.
        let shifted = lines.map { LyricLine(time: max(0, $0.time - offset), text: $0.text) }
        return shifted.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map(\.element)
    }

    /// Drops inline word tags (`<mm:ss.xx>`, as in enhanced `.lrc` files) so they never show as text.
    /// Angle brackets that do not hold a timestamp stay.
    static func strippingWordTags(_ text: Substring) -> String {
        var kept = ""
        var rest = text
        while let open = rest.firstIndex(of: "<") {
            kept += rest[..<open]
            let inside = rest.index(after: open)
            if let close = rest[inside...].firstIndex(of: ">"), stamp(String(rest[inside..<close])) != nil {
                rest = rest[rest.index(after: close)...]
            } else {
                kept.append("<")
                rest = rest[inside...]
            }
        }
        return kept + rest
    }

    /// "01:02.34", "1:02", "00:12.5" in seconds; nil for anything else (a metadata tag).
    static func stamp(_ tag: String) -> Double? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let minutes = Double(parts[0]), minutes >= 0, let seconds = Double(parts[1]), seconds >= 0 else { return nil }
        return minutes * 60 + seconds
    }
}

public extension Array where Element == LyricLine {
    /// The line being sung at `time`: the last one that has started. Nil before the first line.
    func currentIndex(at time: Double) -> Int? {
        guard let first, time >= first.time else { return nil }
        var low = 0, high = count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if self[mid].time <= time { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// How far through the current line (0...1), for a soft fill. Lines last until the next one starts.
    func lineProgress(at time: Double, trackEnd: Double = 0) -> Double {
        guard let index = currentIndex(at: time) else { return 0 }
        let end = index + 1 < count ? self[index + 1].time : Swift.max(trackEnd, self[index].time + 4)
        let span = Swift.max(end - self[index].time, 0.001)
        return Swift.min(Swift.max((time - self[index].time) / span, 0), 1)
    }
}

/// The LRCLIB lookup (https://lrclib.net/api): free, no key. The requests built from it are in LyricsMatching.swift.
public struct LRCLIBQuery: Equatable, Sendable {
    public var artist: String
    public var title: String
    public var album: String
    public var duration: Double

    public init(artist: String, title: String, album: String = "", duration: Double = 0) {
        self.artist = artist; self.title = title; self.album = album; self.duration = duration
    }

    public init(_ playing: NowPlaying) {
        self.init(artist: playing.artist, title: playing.title, album: playing.album, duration: playing.duration)
    }

    /// Needs at least a title; LRCLIB matches on artist too, so a track with neither is not asked about.
    public var isAskable: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !artist.trimmingCharacters(in: .whitespaces).isEmpty }

    /// A stable file name for the cache.
    public var cacheKey: String {
        let basis = [artist, title, album, String(Int(duration.rounded()))].map { $0.lowercased() }.joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(basis.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return digest
    }
}

public enum LRCLIBResponse {
    /// Parses the body of `/api/get`. A 404 body (`{"code":404,...}`) or anything unreadable is `.none`.
    public static func parse(_ data: Data) -> LyricsResult {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .none }
        if object["instrumental"] as? Bool == true { return .instrumental }
        if let synced = object["syncedLyrics"] as? String {
            let lines = LRC.parse(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = object["plainLyrics"] as? String, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .plain(plain) }
        return .none
    }
}

/// Lyrics kept on disk (~/Library/Caches/Zeus/lyrics), one small JSON file per track. Misses are kept too,
/// for `missLifetime`, so a track LRCLIB does not know is not asked about again on every play.
public struct LyricsCache: Sendable {
    public let directory: URL
    public var missLifetime: TimeInterval = 3 * 24 * 3600

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zeus/lyrics", isDirectory: true)
    }

    struct Entry: Codable {
        var kind: String
        var lines: [LyricLine]?
        var plain: String?
        var fetchedAt: Date
    }

    public func load(_ query: LRCLIBQuery, now: Date = Date()) -> LyricsResult? {
        let url = directory.appendingPathComponent(query.cacheKey + ".json")
        guard let data = try? Data(contentsOf: url), let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        switch entry.kind {
        case "synced": return entry.lines.map { .synced($0) }
        case "plain": return entry.plain.map { .plain($0) }
        case "instrumental": return .instrumental
        default: return now.timeIntervalSince(entry.fetchedAt) < missLifetime ? LyricsResult.none : nil
        }
    }

    public func save(_ result: LyricsResult, for query: LRCLIBQuery, now: Date = Date()) {
        var entry = Entry(kind: "none", lines: nil, plain: nil, fetchedAt: now)
        switch result {
        case .synced(let lines): entry.kind = "synced"; entry.lines = lines
        case .plain(let text): entry.kind = "plain"; entry.plain = text
        case .instrumental: entry.kind = "instrumental"
        case .none: break
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: directory.appendingPathComponent(query.cacheKey + ".json"), options: .atomic)
        }
    }
}
