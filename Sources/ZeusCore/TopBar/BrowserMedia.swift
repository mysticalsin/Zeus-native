import Foundation

/// One browser tab's document, named the way the extension names it.
public struct BrowserMediaTarget: Hashable, Sendable {
    public var tabID: Int
    public var documentID: String

    public init(tabID: Int, documentID: String) {
        self.tabID = tabID
        self.documentID = documentID
    }
}

/// What the page's chosen media element says. A live stream has a duration of 0 and cannot be scrubbed.
public struct BrowserMediaElement: Equatable, Sendable {
    public var currentTime: Double
    /// Seconds, 0 when the length is unknown or infinite.
    public var duration: Double
    public var playbackRate: Double
    public var paused: Bool
    public var seekable: Bool
    /// A short hash of the element's source and rounded length. It names the element; it is never the address.
    public var fingerprint: String

    public init(currentTime: Double, duration: Double, playbackRate: Double, paused: Bool, seekable: Bool, fingerprint: String) {
        self.currentTime = currentTime
        self.duration = duration
        self.playbackRate = playbackRate
        self.paused = paused
        self.seekable = seekable
        self.fingerprint = fingerprint
    }
}

/// One tab's media as the extension reports it. The address stays in memory: it goes back to the extension with a
/// command so a navigated page is refused, and nowhere else.
public struct BrowserMediaItem: Equatable, Sendable {
    public var tabID: Int
    public var documentID: String
    public var url: String
    public var title: String
    public var artist: String
    public var album: String
    public var artworkURL: URL?
    public var audible: Bool
    public var element: BrowserMediaElement

    public init(tabID: Int, documentID: String, url: String, title: String, artist: String, album: String,
                artworkURL: URL?, audible: Bool, element: BrowserMediaElement) {
        self.tabID = tabID
        self.documentID = documentID
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.audible = audible
        self.element = element
    }

    /// For display only.
    public var host: String { URL(string: url)?.host ?? "" }

    public var target: BrowserMediaTarget { BrowserMediaTarget(tabID: tabID, documentID: documentID) }

    public var key: BrowserMediaKey {
        BrowserMediaKey(tabID: tabID, documentID: documentID, host: host, fingerprint: element.fingerprint)
    }
}

/// A `media.state` reply, checked. Anything that is not a plain web page, comes from a private window, or has a bad
/// number is dropped here as well as in the extension: the worker is not the only guard.
public struct BrowserMediaState: Equatable, Sendable {
    public var items: [BrowserMediaItem]
    /// Documents the extension was told about that are closed, reloaded or no longer have media.
    public var gone: [BrowserMediaTarget]
    /// The last reply again, because another read was still running.
    public var stale: Bool

    public init(items: [BrowserMediaItem], gone: [BrowserMediaTarget] = [], stale: Bool = false) {
        self.items = items
        self.gone = gone
        self.stale = stale
    }

    /// nil when the reply has no item list at all (a malformed reply). A malformed item is dropped and the rest kept.
    public static func parse(_ value: JSONValue) -> BrowserMediaState? {
        guard let list = value["items"]?.arrayValue else { return nil }
        let items = list.compactMap(parseItem).prefix(BrowserMediaRules.maximumItems)
        let gone = (value["gone"]?.arrayValue ?? []).compactMap(parseTarget).prefix(BrowserMediaRules.maximumGone)
        return BrowserMediaState(items: Array(items), gone: Array(gone), stale: value["stale"]?.boolValue ?? false)
    }

    /// A JSON number only: a string that looks like one is not a number here.
    private static func number(_ value: JSONValue?) -> Double? {
        if case .number(let number)? = value { return number }
        return nil
    }

    private static func integer(_ value: JSONValue?) -> Int? {
        guard let number = number(value), number.isFinite, number >= 0, number < 1_000_000_000_000,
              number.rounded() == number else { return nil }
        return Int(number)
    }

    private static func nonNegative(_ value: JSONValue?) -> Double? {
        guard let number = number(value), number.isFinite, number >= 0 else { return nil }
        return number
    }

    private static func parseTarget(_ value: JSONValue) -> BrowserMediaTarget? {
        guard let tab = integer(value["tabId"]), let document = value["documentId"]?.stringValue,
              !document.isEmpty, document.count <= BrowserMediaRules.maximumIdentifier else { return nil }
        return BrowserMediaTarget(tabID: tab, documentID: document)
    }

    private static func text(_ value: JSONValue?) -> String {
        String((value?.stringValue ?? "").prefix(BrowserMediaRules.maximumText))
    }

    private static func parseItem(_ value: JSONValue) -> BrowserMediaItem? {
        guard value["incognito"]?.boolValue != true,
              let target = parseTarget(value),
              let url = value["url"]?.stringValue, url.count <= BrowserMediaRules.maximumURL,
              let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
              parsed.host?.isEmpty == false,
              case let title = text(value["title"]), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let fingerprint = value["fingerprint"]?.stringValue, !fingerprint.isEmpty,
              fingerprint.count <= BrowserMediaRules.maximumIdentifier,
              let currentTime = nonNegative(value["currentTime"]),
              let rate = nonNegative(value["playbackRate"]),
              let paused = value["paused"]?.boolValue, let seekable = value["seekable"]?.boolValue else { return nil }
        let duration: Double
        switch value["duration"] {
        case nil, .null?: duration = 0
        case let other: guard let number = nonNegative(other) else { return nil }; duration = number
        }
        let element = BrowserMediaElement(currentTime: currentTime, duration: duration, playbackRate: rate,
                                          paused: paused, seekable: seekable, fingerprint: fingerprint)
        return BrowserMediaItem(tabID: target.tabID, documentID: target.documentID, url: url, title: title,
                                artist: text(value["artist"]), album: text(value["album"]),
                                artworkURL: BrowserMediaRules.artworkURL(value["artworkURL"]?.stringValue),
                                audible: value["audible"]?.boolValue ?? false, element: element)
    }
}

/// What a command asks a tab to do.
public struct BrowserMediaCommand: Equatable, Sendable {
    public enum Action: String, Sendable { case play, pause, seek }

    public var action: Action
    public var seconds: Double?
    public var target: BrowserMediaTarget
    public var url: String
    public var fingerprint: String

    /// The request's parameters: the page target in the shape the extension validates (the tab, the document it
    /// was read from, the address, and no need for the tab to be active), the element's fingerprint, the action.
    public func params() -> [String: JSONValue] {
        var result: [String: JSONValue] = [
            "action": .string(action.rawValue),
            "fingerprint": .string(fingerprint),
            "pageTarget": .object([
                "tabId": .number(Double(target.tabID)), "url": .string(url),
                "documentId": .string(target.documentID), "requiresActive": .bool(false),
            ]),
        ]
        if let seconds { result["seconds"] = .number(seconds) }
        return result
    }
}

/// How a failed media request is told.
public enum BrowserMediaFailure: Equatable, Sendable {
    case staleTarget, notSupported, blockedByPage, other

    public init(code: String) {
        switch code {
        case "stale_target": self = .staleTarget
        case "not_supported", "unknown_type": self = .notSupported
        case "blocked_by_page": self = .blockedByPage
        default: self = .other
        }
    }
}

/// What the poll loop needs to know about the notch to choose its pace.
public struct BrowserPollContext: Equatable, Sendable {
    public var followsAny: Bool
    public var outputRunning: Bool
    public var browserShown: Bool
    public var browserShownPlaying: Bool
    public var pausedKnownWithMusicPageOpen: Bool

    public init(followsAny: Bool, outputRunning: Bool = false, browserShown: Bool = false,
                browserShownPlaying: Bool = false, pausedKnownWithMusicPageOpen: Bool = false) {
        self.followsAny = followsAny
        self.outputRunning = outputRunning
        self.browserShown = browserShown
        self.browserShownPlaying = browserShownPlaying
        self.pausedKnownWithMusicPageOpen = pausedKnownWithMusicPageOpen
    }
}

/// The pure rules for browser media: reading a reply into the notch's item, keeping the bar steady between polls,
/// the pace of the poll, and which commands go to a tab.
public enum BrowserMediaRules {
    public static let maximumItems = 4
    public static let maximumGone = 16
    public static let maximumText = 300
    public static let maximumURL = 2048
    public static let maximumIdentifier = 128
    /// A sample moves the bar only when it differs from the prediction by more than this many seconds.
    public static let reanchorTolerance = 0.75
    public static let playingDelay: TimeInterval = 2
    public static let idleDelay: TimeInterval = 5

    /// The first extension version that answers `media.state` and `media.command`.
    public static let minimumVersion = [0, 5, 0]

    /// A cover link a page named. https only, never `data:`, `blob:` or `http:`, and short.
    public static func artworkURL(_ text: String?) -> URL? {
        guard let text, text.count <= maximumURL, let url = URL(string: text),
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return nil }
        return url
    }

    /// The notch's item for a tab, with the position anchored at `anchor`.
    public static func nowPlaying(_ item: BrowserMediaItem, anchor: Date) -> NowPlaying {
        NowPlaying(source: .browser(item.key), title: item.title, artist: item.artist, album: item.album,
                   isPlaying: !item.element.paused, duration: item.element.duration, position: item.element.currentTime,
                   positionAt: anchor, rate: item.element.playbackRate, artworkURL: item.artworkURL)
    }

    /// Where the position has got to `elapsed` seconds after it was read: it advances by the rate while the
    /// element plays, holds at rate 0 or when paused, and stays inside the length when there is one.
    public static func extrapolate(position: Double, rate: Double, duration: Double, isPlaying: Bool, elapsed: TimeInterval) -> Double {
        guard isPlaying else { return position }
        let value = position + max(elapsed, 0) * max(rate, 0)
        return duration > 0 ? min(value, duration) : value
    }

    public static func shouldReanchor(predicted: Double, observed: Double) -> Bool {
        abs(predicted - observed) > reanchorTolerance
    }

    /// Keeps the previous item, anchor and all, when the new sample agrees with where it predicted the bar to be, so
    /// the hub sees an equal value and writes nothing. A different track, a pause, a rate change or a seek re-anchors.
    public static func merged(previous: NowPlaying?, sample: NowPlaying) -> NowPlaying {
        guard let previous, previous.source == sample.source, previous.title == sample.title,
              previous.artist == sample.artist, previous.album == sample.album, previous.isPlaying == sample.isPlaying,
              previous.duration == sample.duration, previous.rate == sample.rate,
              previous.artworkURL == sample.artworkURL else { return sample }
        let predicted = extrapolate(position: previous.position, rate: previous.rate, duration: previous.duration,
                                    isPlaying: previous.isPlaying, elapsed: sample.positionAt.timeIntervalSince(previous.positionAt))
        return shouldReanchor(predicted: predicted, observed: sample.position) ? sample : previous
    }

    /// Seconds until the next poll, nil for none. Never under a pin. Otherwise only while Chrome plays sound, a
    /// browser item is shown, or a paused one is known and the Music page is open.
    public static func pollDelay(_ context: BrowserPollContext) -> TimeInterval? {
        guard context.followsAny,
              context.outputRunning || context.browserShown || context.pausedKnownWithMusicPageOpen else { return nil }
        return context.browserShown && context.browserShownPlaying ? playingDelay : idleDelay
    }

    /// The items the notch may use. While a call runs in a browser, none: a call is never shown or paused.
    public static func usable(_ items: [BrowserMediaItem], callPresent: Bool) -> [BrowserMediaItem] {
        callPresent ? [] : items
    }

    /// The tab command for a music command, nil when a tab cannot honour it. Next and previous have no path: an
    /// extension cannot call a page's media session handlers. Nothing goes to a tab while a browser call runs.
    public static func command(for kind: MusicCommandKind, seconds: Double?, item: BrowserMediaItem,
                               callPresent: Bool = false) -> BrowserMediaCommand? {
        guard !callPresent else { return nil }
        let action: BrowserMediaCommand.Action
        var target: Double?
        switch kind {
        case .play: action = .play
        case .pause: action = .pause
        case .playPause: action = item.element.paused ? .play : .pause
        case .seek:
            guard item.element.seekable, item.element.duration > 0, let seconds, seconds.isFinite else { return nil }
            action = .seek
            target = MusicSeek.clampedTarget(seconds, duration: item.element.duration)
        case .next, .previous, .open, .toggleShuffle, .cycleRepeat: return nil
        }
        return BrowserMediaCommand(action: action, seconds: target, target: item.target, url: item.url,
                                   fingerprint: item.element.fingerprint)
    }

    /// Whether an extension of this version answers the media requests.
    public static func extensionSupportsMedia(version: String?) -> Bool {
        guard let version, !version.isEmpty else { return false }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count <= 4, parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return false }
        var numbers = parts.compactMap { $0 }
        while numbers.count < minimumVersion.count { numbers.append(0) }
        for (have, need) in zip(numbers, minimumVersion) where have != need { return have > need }
        return true
    }
}
