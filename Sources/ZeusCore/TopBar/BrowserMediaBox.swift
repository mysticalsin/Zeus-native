import Foundation

/// Browser media answers: which title is visible, how the bar moves, how often to poll,
/// and which command a tab can take. This type does not read a screen, a pointer, a clock,
/// or a stored setting, and it does not talk to an extension.
public enum BrowserMediaBox {
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

    /// Spaces and line breaks, named as scalars. U+200B is not a member. Linux
    /// `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so a title is not asked of that set.
    public static let blankScalars: Set<Unicode.Scalar> = [
        "\u{0009}", "\u{000A}", "\u{000B}", "\u{000C}", "\u{000D}",
        "\u{0020}",
        "\u{0085}",
        "\u{00A0}",
        "\u{1680}",
        "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}",
        "\u{2005}", "\u{2006}", "\u{2007}", "\u{2008}", "\u{2009}", "\u{200A}",
        "\u{2028}", "\u{2029}",
        "\u{202F}",
        "\u{205F}",
        "\u{3000}",
    ]

    /// True when `title` has a scalar outside `blankScalars`. Empty is not a title.
    /// A zero-width space is a title.
    public static func titleIsVisible(_ title: String) -> Bool {
        title.unicodeScalars.contains { !blankScalars.contains($0) }
    }

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
    /// A negative elapsed and a negative rate hold the position.
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
