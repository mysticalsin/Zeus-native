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
              case let title = text(value["title"]), BrowserMediaBox.titleIsVisible(title),
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

/// The pure rules for browser media. Each answer is read from `BrowserMediaBox`.
public enum BrowserMediaRules {
    public static let maximumItems = BrowserMediaBox.maximumItems
    public static let maximumGone = BrowserMediaBox.maximumGone
    public static let maximumText = BrowserMediaBox.maximumText
    public static let maximumURL = BrowserMediaBox.maximumURL
    public static let maximumIdentifier = BrowserMediaBox.maximumIdentifier
    public static let reanchorTolerance = BrowserMediaBox.reanchorTolerance
    public static let playingDelay = BrowserMediaBox.playingDelay
    public static let idleDelay = BrowserMediaBox.idleDelay
    public static let minimumVersion = BrowserMediaBox.minimumVersion

    public static func artworkURL(_ text: String?) -> URL? {
        BrowserMediaBox.artworkURL(text)
    }

    public static func nowPlaying(_ item: BrowserMediaItem, anchor: Date) -> NowPlaying {
        BrowserMediaBox.nowPlaying(item, anchor: anchor)
    }

    public static func extrapolate(position: Double, rate: Double, duration: Double, isPlaying: Bool, elapsed: TimeInterval) -> Double {
        BrowserMediaBox.extrapolate(position: position, rate: rate, duration: duration, isPlaying: isPlaying, elapsed: elapsed)
    }

    public static func shouldReanchor(predicted: Double, observed: Double) -> Bool {
        BrowserMediaBox.shouldReanchor(predicted: predicted, observed: observed)
    }

    public static func merged(previous: NowPlaying?, sample: NowPlaying) -> NowPlaying {
        BrowserMediaBox.merged(previous: previous, sample: sample)
    }

    public static func pollDelay(_ context: BrowserPollContext) -> TimeInterval? {
        BrowserMediaBox.pollDelay(context)
    }

    public static func usable(_ items: [BrowserMediaItem], callPresent: Bool) -> [BrowserMediaItem] {
        BrowserMediaBox.usable(items, callPresent: callPresent)
    }

    public static func command(for kind: MusicCommandKind, seconds: Double?, item: BrowserMediaItem,
                               callPresent: Bool = false) -> BrowserMediaCommand? {
        BrowserMediaBox.command(for: kind, seconds: seconds, item: item, callPresent: callPresent)
    }

    public static func extensionSupportsMedia(version: String?) -> Bool {
        BrowserMediaBox.extensionSupportsMedia(version: version)
    }
}
