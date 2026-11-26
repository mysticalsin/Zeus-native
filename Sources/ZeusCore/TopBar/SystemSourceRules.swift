import Foundation

/// Pure slot and command rules for one system now-playing item. The feed applies the result.
/// This type keeps no clock and starts nothing.
public enum SystemSourceRules {
    /// `CFBundleIdentifier` in `Resources/Info.plist`. An item from this app is proof, never a shown entry.
    public static let zeusBundleID = "app.zeus.mac"

    /// A service time older than this is not used as the position anchor.
    public static let positionWindow: TimeInterval = 86_400

    /// An app, title or artist may change at most once per this many seconds.
    public static let identityGap: TimeInterval = 1

    /// Shown when the feed has no app name.
    public static let unknownAppName = "This Mac"

    /// One item the helper reported. Text is already cleaned by the wire.
    public struct Item: Equatable, Sendable {
        public var app: String
        public var parent: String
        public var title: String
        public var artist: String
        public var album: String
        public var duration: Double
        public var elapsed: Double
        /// The service's own time stamp, when it sent one.
        public var at: Date?
        public var rate: Double
        public var key: String

        public init(app: String, parent: String = "", title: String = "", artist: String = "", album: String = "",
                    duration: Double = 0, elapsed: Double = 0, at: Date? = nil, rate: Double = 0, key: String = "") {
            self.app = app
            self.parent = parent
            self.title = title
            self.artist = artist
            self.album = album
            self.duration = duration
            self.elapsed = elapsed
            self.at = at
            self.rate = rate
            self.key = key
        }
    }

    /// Why an item is kept out, or that it may be shown. `none` is the absence of an item.
    public enum Verdict: Equatable, Sendable {
        case own
        case callApp
        case shadowedByPlayer
        case shadowedByBrowser
        case show
    }

    /// The value a shown item becomes. It never offers lyrics, shuffle or repeat.
    public struct Shown: Equatable, Sendable {
        public var appBundleID: String
        public var appName: String
        public var title: String
        public var artist: String
        public var album: String
        public var isPlaying: Bool
        public var duration: Double
        public var position: Double
        public var positionAt: Date
        public var rate: Double
        public var key: String
        public var capabilities: SourceCapabilities

        public init(appBundleID: String, appName: String, title: String, artist: String, album: String,
                    isPlaying: Bool, duration: Double, position: Double, positionAt: Date, rate: Double, key: String,
                    capabilities: SourceCapabilities) {
            self.appBundleID = appBundleID
            self.appName = appName
            self.title = title
            self.artist = artist
            self.album = album
            self.isPlaying = isPlaying
            self.duration = duration
            self.position = position
            self.positionAt = positionAt
            self.rate = rate
            self.key = key
            self.capabilities = capabilities
        }
    }

    /// What the feed does with the single system slot.
    public enum Slot: Equatable, Sendable {
        case clear
        case replace
        case update
    }

    /// A command the wire can carry. Shuffle, repeat and open are not commands here.
    public struct Command: Equatable, Sendable {
        public enum Name: String, Equatable, Sendable {
            case play, pause, next, previous, seek
        }

        public var name: Name
        public var seconds: Double
        public var app: String

        public init(name: Name, seconds: Double, app: String) {
            self.name = name
            self.seconds = seconds
            self.app = app
        }
    }

    /// Own, then a native call, then Music or Spotify, then a browser whose own feed is on. Anything else is shown.
    /// A parent bundle id is checked with the app's, so a helper does not hide the app it belongs to.
    public static func verdict(item: Item, ownBundleID: String, browserFeedActive: Bool) -> Verdict {
        let bundles = [item.app, item.parent]
        if bundles.contains(where: { isOwn($0, ownBundleID: ownBundleID) }) { return .own }
        if bundles.contains(where: isNativeCall) { return .callApp }
        if bundles.contains(where: { NowPlaying.Player(bundleID: $0) != nil }) { return .shadowedByPlayer }
        if browserFeedActive, bundles.contains(where: ScribeCallDetection.isBrowser) { return .shadowedByBrowser }
        return .show
    }

    /// Maps a shown item. The position anchors on the service time when that time is inside the last day and not
    /// in the future. Rate 0 is paused. A duration that is missing, zero or not finite cannot seek.
    /// A zero-width space stays in the app name. The blank check is read from `SystemSourceRulesBox`.
    public static func nowPlaying(_ item: Item, appName: String, receivedAt: Date) -> Shown {
        let duration = finiteNonNegative(item.duration)
        var capabilities: SourceCapabilities = [.playPause, .next, .previous]
        if duration > 0 { capabilities.insert(.seek) }
        let rate = finiteNonNegative(item.rate)
        let name = SystemSourceRulesBox.trimmedName(appName)
        return Shown(appBundleID: item.app, appName: name.isEmpty ? unknownAppName : name, title: item.title,
                     artist: item.artist, album: item.album, isPlaying: rate > 0, duration: duration,
                     position: finiteNonNegative(item.elapsed), positionAt: anchor(item.at, receivedAt: receivedAt),
                     rate: rate, key: item.key, capabilities: capabilities)
    }

    /// Position-only updates pass. A change of app, title or artist passes at most once a second.
    public static func forward(previous: Item?, next: Item, lastIdentityChange: Date, now: Date) -> Bool {
        guard let previous, identity(previous) == identity(next) else {
            let gap = now.timeIntervalSince(lastIdentityChange)
            guard gap.isFinite else { return false }
            return gap >= identityGap
        }
        return true
    }

    /// `none` and every verdict but `show` clear the slot. A new key replaces. The same key updates.
    public static func slot(verdict: Verdict?, key: String, current: String?) -> Slot {
        guard verdict == .show else { return .clear }
        guard let current, current == key else { return .replace }
        return .update
    }

    /// `playPause` is pause while the rate is above 0, and play otherwise. Shuffle, repeat, open, a seek on live
    /// content, and a key other than the one shown are nil.
    public static func command(for kind: MusicCommandKind, item: Item, seconds: Double, key: String) -> Command? {
        guard !key.isEmpty, item.key == key else { return nil }
        let name: Command.Name
        switch kind {
        case .play: name = .play
        case .pause: name = .pause
        case .playPause: name = finiteNonNegative(item.rate) > 0 ? .pause : .play
        case .next: name = .next
        case .previous: name = .previous
        case .seek:
            guard finiteNonNegative(item.duration) > 0 else { return nil }
            name = .seek
        case .open, .toggleShuffle, .cycleRepeat:
            return nil
        }
        let held = name == .seek ? finiteNonNegative(seconds) : 0
        return Command(name: name, seconds: held, app: item.app)
    }

    private static func isOwn(_ bundleID: String, ownBundleID: String) -> Bool {
        guard !ownBundleID.isEmpty else { return false }
        return bundleID.caseInsensitiveCompare(ownBundleID) == .orderedSame
    }

    /// A native call app, by bundle id. A browser is not one: that needs a window title, which this feature does not read.
    private static func isNativeCall(_ bundleID: String) -> Bool {
        ScribeCallDetection.identify(bundleID: bundleID) != nil
    }

    private static func identity(_ item: Item) -> (String, String, String) {
        (item.app, item.title, item.artist)
    }

    private static func anchor(_ at: Date?, receivedAt: Date) -> Date {
        guard let at else { return receivedAt }
        let age = receivedAt.timeIntervalSince(at)
        guard age.isFinite, age >= 0, age <= positionWindow else { return receivedAt }
        return at
    }

    private static func finiteNonNegative(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return value
    }
}
