import Foundation

/// Title and artist clean-up for the lyric lookup. The suffix rules are a small subset ported from
/// web-scrobbler/metadata-filter (MIT, see NOTICES.md). "Live" is never stripped: a live recording keeps its title.
public enum LyricsTitle {
    private static let year = "(?:19|20)[0-9]{2}"
    private static let remaster = "(?:\(year)\\s+)?(?:digital(?:ly)?\\s+)?remaster(?:ed)?(?:\\s+\(year))?(?:\\s+version)?"
    private static let deluxe = "(?:super\\s+)?deluxe(?:\\s+(?:edition|version))?"
    private static let edition = "(?:expanded|special|anniversary|collector'?s|limited)\\s+(?:edition|version)"
    private static let version = "(?:single|album)\\s+version|radio\\s+(?:edit|version)|(?:mono|stereo)\\s+(?:version|mix)|(?:explicit|clean)\\s+version"
    private static let bonus = "bonus\\s+track(?:\\s+version)?"
    /// Only safe inside brackets, where a lone word is clearly a tag and not part of the title.
    private static let bracketOnly = "explicit|clean|mono|stereo"
    private static let credit = "(?:(?:feat|ft)\\.\\s*|(?:feat|ft|featuring)\\s+)[^\\)\\]]+"
    private static let dashes = "[-\\x{2013}\\x{2014}]"

    private static let both = [remaster, deluxe, edition, version, bonus].joined(separator: "|")

    /// Each pattern matches one suffix at the end of the title.
    private static let suffixes = [
        "\\s*[\\(\\[]\\s*(?:\(both)|\(bracketOnly))\\s*[\\)\\]]\\s*$",
        "\\s*[\\(\\[]\\s*\(credit)[\\)\\]]\\s*$",
        "\\s+\(dashes)\\s+(?:\(both))\\s*$",
    ]

    /// The title without version suffixes. Unchanged (the very same text) when no rule applies, and never empty.
    public static func stripped(_ title: String) -> String {
        var current = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var removed = false
        var rounds = 0
        search: while rounds < 6 {
            for pattern in suffixes {
                if let range = current.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    current.removeSubrange(range)
                    current = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    removed = true
                    rounds += 1
                    continue search
                }
            }
            break
        }
        return removed && !current.isEmpty ? current : title
    }

    private static let featuredSeparators = [" feat. ", " feat ", " ft. ", " ft ", " featuring "]
    private static let artistSeparators = [",", ";", " & ", " / "] + featuredSeparators

    /// The first credited artist: "Queen & David Bowie" is "Queen". Unchanged when only one is credited.
    /// It cuts acts like "Simon & Garfunkel" too, so it only feeds the search, which a length check backs up.
    public static func primaryArtist(_ artist: String) -> String { head(of: artist, at: artistSeparators) }

    /// The artist without a featured credit: "Artist A feat. Artist B" is "Artist A". "&" and "," stay, so
    /// "Earth, Wind & Fire" is unchanged. For the exact-match request, where a half of a group name finds nothing.
    public static func withoutFeaturedArtists(_ artist: String) -> String { head(of: artist, at: featuredSeparators) }

    private static func head(of artist: String, at separators: [String]) -> String {
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cuts = separators.compactMap { trimmed.range(of: $0, options: .caseInsensitive)?.lowerBound }
        guard let cut = cuts.min() else { return artist }
        let first = trimmed[..<cut].trimmingCharacters(in: .whitespacesAndNewlines)
        return first.isEmpty ? artist : first
    }
}

/// One answer from `/api/search`.
public struct LyricsCandidate: Equatable, Sendable {
    public var id: Int
    public var title: String
    public var artist: String
    public var duration: Double
    public var instrumental: Bool
    public var syncedText: String?
    public var plainText: String?

    public init(id: Int, title: String, artist: String, duration: Double, instrumental: Bool,
                syncedText: String?, plainText: String?) {
        self.id = id; self.title = title; self.artist = artist; self.duration = duration
        self.instrumental = instrumental; self.syncedText = syncedText; self.plainText = plainText
    }

    /// What this candidate holds, read the same way as a `/api/get` body.
    public var result: LyricsResult {
        if instrumental { return .instrumental }
        if let syncedText {
            let lines = LRC.parse(syncedText)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plainText, !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .plain(plainText) }
        return .none
    }
}

public extension LRCLIBResponse {
    /// Parses the body of `/api/search`: an array of tracks. Anything unreadable gives an empty list.
    static func parseSearch(_ data: Data) -> [LyricsCandidate] {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        func text(_ value: Any?) -> String? {
            guard let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return string
        }
        return array.compactMap { element in
            guard let object = element as? [String: Any] else { return nil }
            return LyricsCandidate(
                id: (object["id"] as? NSNumber)?.intValue ?? 0,
                title: (object["trackName"] as? String) ?? (object["name"] as? String) ?? "",
                artist: (object["artistName"] as? String) ?? "",
                duration: (object["duration"] as? NSNumber)?.doubleValue ?? 0,
                instrumental: object["instrumental"] as? Bool == true,
                syncedText: text(object["syncedLyrics"]),
                plainText: text(object["plainLyrics"]))
        }
    }
}

/// Picks the search result that is the playing recording.
public enum LyricsMatch {
    /// How far a candidate's length may be from the track's: 2 seconds, or 3 percent of the track if that is larger.
    public static func window(for duration: Double) -> Double { max(2, duration * 3 / 100) }

    private static func plain(_ title: String) -> String { title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    /// Synced before plain before instrumental, inside the duration window, then the nearest duration (the earlier one
    /// on a tie). With an unknown duration (0) only a candidate whose title equals `title`, the title as the player
    /// reports it, ignoring case, is taken: a version suffix on either side is a different recording. Candidates with
    /// nothing to show are skipped.
    public static func best(_ candidates: [LyricsCandidate], duration: Double, title: String) -> LyricsCandidate? {
        let wanted = Self.plain(title)
        var pick: (rank: Int, distance: Double, index: Int)?
        for (index, candidate) in candidates.enumerated() {
            let rank: Int
            switch candidate.result {
            case .synced: rank = 0
            case .plain: rank = 1
            case .instrumental: rank = 2
            case .none: continue
            }
            var distance = 0.0
            if duration > 0 {
                distance = abs(candidate.duration - duration)
                guard candidate.duration > 0, distance <= window(for: duration) else { continue }
            } else if Self.plain(candidate.title) != wanted {
                continue
            }
            let entry = (rank: rank, distance: distance, index: index)
            if let current = pick, (current.rank, current.distance, current.index) <= (entry.rank, entry.distance, entry.index) { continue }
            pick = entry
        }
        return pick.map { candidates[$0.index] }
    }
}

/// One of the three lookups, with its URL already built.
public struct LyricsRequest: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// `/api/get` with the track exactly as the player reports it.
        case exact
        /// `/api/get` with the cleaned title and the artist without a featured credit, no album.
        case cleaned
        /// `/api/search` with the cleaned title and first artist.
        case search
    }

    public var step: Step
    public var url: URL

    /// What a 200 body means for this step. `.none` means this step found nothing, so the next one may run.
    public func result(from data: Data, query: LRCLIBQuery) -> LyricsResult {
        switch step {
        case .exact, .cleaned:
            return LRCLIBResponse.parse(data)
        case .search:
            let list = LRCLIBResponse.parseSearch(data)
            return LyricsMatch.best(list, duration: query.duration, title: query.title)?.result ?? .none
        }
    }
}

public extension LRCLIBQuery {
    /// The title with version suffixes removed. Step 3 also uses the first credited artist.
    private var cleanedTitle: String { LyricsTitle.stripped(title) }
    private var cleanedArtist: String { LyricsTitle.primaryArtist(artist) }
    /// For the exact-match step only a featured credit is cut: "Earth, Wind & Fire" is one act.
    private var cleanedGetArtist: String { LyricsTitle.withoutFeaturedArtists(artist) }

    /// The whole seconds LRCLIB's `/api/get` takes for the length: 1 to 3600. Nil for anything else
    /// (unknown, under half a second, over an hour, not a number), which it answers with a 400.
    var requestSeconds: Int? {
        guard duration.isFinite, duration >= 0.5, duration < 3600.5 else { return nil }
        return Int(duration.rounded())
    }

    /// Step 1: today's strict request. Nil for a track that is not askable.
    var exactRequest: LyricsRequest? {
        guard isAskable else { return nil }
        var items = [("artist_name", artist), ("track_name", title), ("album_name", album)]
        if let seconds = requestSeconds { items.append(("duration", String(seconds))) }
        return Self.request(.exact, path: "/api/get", items)
    }

    /// Step 2, only when clean-up changed the title or cut a featured artist, and only with a length LRCLIB takes: the old
    /// request without a length could return another recording's timing.
    var cleanedRequest: LyricsRequest? {
        guard isAskable, let seconds = requestSeconds, cleanedTitle != title || cleanedGetArtist != artist else { return nil }
        return Self.request(.cleaned, path: "/api/get", [
            ("artist_name", cleanedGetArtist), ("track_name", cleanedTitle), ("duration", String(seconds)),
        ])
    }

    /// Step 3: a search by cleaned title and first artist, judged by `LyricsMatch.best`.
    var searchRequest: LyricsRequest? {
        guard isAskable else { return nil }
        return Self.request(.search, path: "/api/search", [("artist_name", cleanedArtist), ("track_name", cleanedTitle)])
    }

    /// The lookups in the order they run; the next one runs only after a 404 or a body without lyrics.
    var requests: [LyricsRequest] { [exactRequest, cleanedRequest, searchRequest].compactMap { $0 } }

    /// The URL of the strict request.
    var url: URL? { exactRequest?.url }

    /// Every query value is percent-encoded down to the unreserved characters, so "&" and "+" in a name
    /// reach the server as themselves.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func request(_ step: LyricsRequest.Step, path: String, _ items: [(String, String)]) -> LyricsRequest? {
        func encode(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "" }
        let query = items.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
        guard let url = URL(string: "https://lrclib.net\(path)?\(query)") else { return nil }
        return LyricsRequest(step: step, url: url)
    }
}

/// How the lyrics service answered one request.
public enum LyricsFetchOutcome: Equatable, Sendable {
    /// HTTP 200: there is a body to read.
    case found
    /// HTTP 404, or another 4xx that refuses this one request (400 and the like): the service answered and has
    /// nothing for it, so the next step may run. It says nothing about the service being down.
    case notFound
    /// No answer, 408, 429, 5xx or anything unexpected. Never cached; `retryAfter` is the server's wait in seconds, if it sent one.
    case failed(retryAfter: TimeInterval?)
}

public enum LyricsStatus {
    /// Maps an HTTP status code. 200 is a body, and a 4xx other than 408 and 429 is the service refusing this request
    /// (404 has nothing, 400 is a value it cannot take): both are answers. Everything else is a failure, so it is
    /// never cached as "no lyrics" and it starts the shared wait.
    public static func outcome(status: Int, retryAfter: TimeInterval?) -> LyricsFetchOutcome {
        switch status {
        case 200: .found
        case 408, 429: .failed(retryAfter: retryAfter)
        case 400...499: .notFound
        default: .failed(retryAfter: retryAfter)
        }
    }

    /// The `Retry-After` header as seconds from `now`: whole seconds or an HTTP date. Nil when absent or unreadable.
    public static func retryAfter(header: String?, now: Date) -> TimeInterval? {
        guard let text = header?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if let seconds = Double(text) { return seconds.isFinite && seconds >= 0 ? seconds : nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: text) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }
}

/// What the one retry after a failure does at a wake-up.
public enum LyricsRetryPlan: Equatable, Sendable {
    /// The wait is not over: sleep this many seconds, then decide again.
    case wait(TimeInterval)
    /// Send the single request now.
    case askNow
    /// Send nothing. A later load of the same track from a lyric view starts over.
    case stop
}

public enum LyricsRetry {
    /// Decides the retry after a failure. It goes out only for the track that is still current and unanswered,
    /// while it plays, with a lyric view on screen and lyrics switched on; otherwise it stops, so a closed notch,
    /// paused music or a stopped player never causes a request. While the wait runs it sleeps for what is left.
    public static func plan(remaining: TimeInterval, sameTrack: Bool, isPlaying: Bool, visible: Bool, enabled: Bool) -> LyricsRetryPlan {
        guard enabled, sameTrack, isPlaying, visible else { return .stop }
        return remaining > 0 ? .wait(remaining) : .askNow
    }
}

/// The wait after the lyrics service fails, shared by every track: 30 seconds, doubling to 15 minutes, or the
/// server's Retry-After (at most an hour). A success clears it.
public struct LyricsBackoff: Equatable, Sendable {
    public static let firstDelay: TimeInterval = 30
    public static let ceiling: TimeInterval = 15 * 60
    public static let longestRetryAfter: TimeInterval = 60 * 60

    public private(set) var failures = 0
    public private(set) var blockedUntil: Date?

    public init() {}

    /// A failure always counts, so the sequence keeps doubling across a Retry-After. A zero or negative one is ignored.
    public mutating func recordFailure(now: Date, retryAfter: TimeInterval? = nil) {
        failures += 1
        let doubled = min(Self.ceiling, Self.firstDelay * pow(2, Double(min(failures - 1, 16))))
        let delay = retryAfter.flatMap { $0 > 0 ? min($0, Self.longestRetryAfter) : nil } ?? doubled
        blockedUntil = now.addingTimeInterval(delay)
    }

    public mutating func recordSuccess() {
        failures = 0
        blockedUntil = nil
    }

    public func canAsk(now: Date) -> Bool { remaining(now: now) <= 0 }

    /// Seconds left to wait, 0 when a request may go out.
    public func remaining(now: Date) -> TimeInterval {
        guard let blockedUntil else { return 0 }
        return max(0, blockedUntil.timeIntervalSince(now))
    }
}
