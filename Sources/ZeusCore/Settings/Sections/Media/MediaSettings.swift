import Foundation

/// Where the Media section sits once the shell can place a section. Order 1 is the first top bar tab.
public enum MediaSectionPlacement {
    public static let topbarTab = 1
}

/// The defaults key is the same prefix the settings store already uses.
public enum MediaDefaultsKey {
    public static let prefix = "opt."

    public static func stored(_ id: String) -> String { prefix + id }
}

/// Held rows stay on the page and do nothing. Animated artwork is not implemented.
public enum MediaHeldFeature {
    public static let heldNote = "Coming later"
    public static let animatedArtworkImplemented = false
    public static let systemNowPlayingImplemented = false
}

/// Keys this section reads. Existing keys keep their names. Added keys are the ones that had no home.
public enum MediaSettingID {
    public static let follow = "music.follow"
    public static let homeMusic = "home.variant.music"
    public static let playerLook = "media.playerLook"
    public static let tint = "media.tintFromSong"
    public static let like = "media.likeFollowsSong"
    public static let explicitBadge = "media.explicitBadge"
    public static let explicitColour = "media.explicitMatchColour"
    public static let waveform = "topBar.musicWings"
    public static let lyrics = "privacy.lyrics"
    public static let wordByWord = "lyrics.wordByWord"
    public static let shuffleRepeat = "media.shuffleRepeat"
    public static let leftButton = "media.leftButton"
    public static let hideOnPause = "media.hideOnPause"
    public static let openTrigger = "notch.openTrigger"
    public static let keepAwake = "keepAwake.whileMusic"
    public static let equaliser = "audio.equaliser"
    public static let browser = "music.browserMedia"
    public static let animatedArtwork = "media.animatedArtwork"
    public static let systemNowPlaying = "media.systemNowPlaying"

    public static let existing = [
        follow, homeMusic, waveform, lyrics, wordByWord, openTrigger, keepAwake, equaliser, browser,
    ]
    public static let added = [
        playerLook, tint, like, explicitBadge, explicitColour, leftButton, hideOnPause,
    ]
}

/// The home widget's music card. Its stored choices stay as they are.
public enum MediaHomeMusicStyle {
    public static let choices = ["Art", "Disc", "Cassette", "Wave", "Lyrics"]
    public static let `default` = "Art"

    public static func resolve(_ stored: String?) -> String {
        guard let stored, choices.contains(stored) else { return Self.default }
        return stored
    }
}

/// Synced lyrics use the network only while the switch is on.
public enum MediaLyricsPolicy {
    public static let defaultEnabled = false

    public static func mayUseNetwork(enabled: Bool) -> Bool { enabled }
}

/// An import can turn a protected switch off. It cannot turn one on.
public enum MediaImportGuard {
    public static let protected = [MediaSettingID.lyrics, MediaSettingID.browser, MediaSettingID.equaliser]

    public static func value(id: String, imported: String?, current: String?) -> String? {
        if protected.contains(id), imported == "true" { return current }
        return imported ?? current
    }
}

/// How the notch player is drawn. This is separate from the home widget's music card.
public enum MediaPlayerLook: String, CaseIterable, Sendable, Equatable {
    case art
    case glassArt
    case glassCard
    case detailed

    public var title: String {
        switch self {
        case .art: "Art"
        case .glassArt: "Glass art"
        case .glassCard: "Glass card"
        case .detailed: "Detailed"
        }
    }

    public var showsArt: Bool { self != .glassCard }
    public var usesGlass: Bool { self != .art }
    public var showsDetail: Bool { self == .detailed }

    public init(stored: String?) { self = Self(rawValue: stored ?? "") ?? .art }
}

/// The button to the left of play.
public enum MediaLeftButton: String, CaseIterable, Sendable, Equatable {
    case previous
    case like
    case lyrics

    public var title: String {
        switch self {
        case .previous: "Previous"
        case .like: "Like"
        case .lyrics: "Lyrics"
        }
    }

    public var symbol: String {
        switch self {
        case .previous: "backward.fill"
        case .like: "heart.fill"
        case .lyrics: "quote.bubble"
        }
    }

    public init(stored: String?) { self = Self(rawValue: stored ?? "") ?? .previous }
}

/// Hover or click, stored with the words the notch already reads.
public enum MediaOpenTrigger: String, CaseIterable, Sendable, Equatable {
    case hover = "Hover"
    case click = "Click"

    public init(stored: String?) { self = Self(rawValue: stored ?? "") ?? .hover }
}

/// One saved Media page. Missing and unknown values use the defaults, so a bad store cannot turn the network on.
public struct MediaSettings: Equatable, Sendable {
    public var follow: NowPlayingArbiter.Follow
    public var homeMusic: String
    public var look: MediaPlayerLook
    public var tintFromSong: Bool
    public var likeFollowsSong: Bool
    public var explicitBadge: Bool
    public var explicitMatchesColour: Bool
    public var waveform: Bool
    public var lyrics: Bool
    public var wordByWord: Bool
    public var leftButton: MediaLeftButton
    public var hideOnPause: MediaHidePolicy
    public var openTrigger: MediaOpenTrigger
    public var keepAwake: Bool
    public var equaliser: Bool
    public var browserMedia: Bool

    public init(follow: NowPlayingArbiter.Follow, homeMusic: String, look: MediaPlayerLook, tintFromSong: Bool,
                likeFollowsSong: Bool, explicitBadge: Bool, explicitMatchesColour: Bool, waveform: Bool, lyrics: Bool,
                wordByWord: Bool, leftButton: MediaLeftButton, hideOnPause: MediaHidePolicy, openTrigger: MediaOpenTrigger,
                keepAwake: Bool, equaliser: Bool, browserMedia: Bool) {
        self.follow = follow
        self.homeMusic = homeMusic
        self.look = look
        self.tintFromSong = tintFromSong
        self.likeFollowsSong = likeFollowsSong
        self.explicitBadge = explicitBadge
        self.explicitMatchesColour = explicitMatchesColour
        self.waveform = waveform
        self.lyrics = lyrics
        self.wordByWord = wordByWord
        self.leftButton = leftButton
        self.hideOnPause = hideOnPause
        self.openTrigger = openTrigger
        self.keepAwake = keepAwake
        self.equaliser = equaliser
        self.browserMedia = browserMedia
    }

    public static let defaults = MediaSettings(
        follow: .any, homeMusic: MediaHomeMusicStyle.default, look: .art, tintFromSong: false, likeFollowsSong: false,
        explicitBadge: false, explicitMatchesColour: false, waveform: true, lyrics: false, wordByWord: true,
        leftButton: .previous, hideOnPause: .never, openTrigger: .hover, keepAwake: false, equaliser: false, browserMedia: false
    )

    public init(reading value: (String) -> String?) {
        func text(_ id: String) -> String? {
            let raw = value(id)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let raw, !raw.isEmpty else { return nil }
            return raw
        }
        func flag(_ id: String, default defaultValue: Bool) -> Bool {
            switch text(id) {
            case "true": true
            case "false": false
            default: defaultValue
            }
        }
        let base = Self.defaults
        follow = NowPlayingArbiter.Follow(label: text(MediaSettingID.follow))
        homeMusic = MediaHomeMusicStyle.resolve(text(MediaSettingID.homeMusic))
        look = MediaPlayerLook(stored: text(MediaSettingID.playerLook))
        tintFromSong = flag(MediaSettingID.tint, default: base.tintFromSong)
        likeFollowsSong = flag(MediaSettingID.like, default: base.likeFollowsSong)
        explicitBadge = flag(MediaSettingID.explicitBadge, default: base.explicitBadge)
        explicitMatchesColour = flag(MediaSettingID.explicitColour, default: base.explicitMatchesColour)
        waveform = flag(MediaSettingID.waveform, default: base.waveform)
        lyrics = flag(MediaSettingID.lyrics, default: base.lyrics)
        wordByWord = flag(MediaSettingID.wordByWord, default: base.wordByWord)
        leftButton = MediaLeftButton(stored: text(MediaSettingID.leftButton))
        hideOnPause = MediaHidePolicy(stored: text(MediaSettingID.hideOnPause))
        openTrigger = MediaOpenTrigger(stored: text(MediaSettingID.openTrigger))
        keepAwake = flag(MediaSettingID.keepAwake, default: base.keepAwake)
        equaliser = flag(MediaSettingID.equaliser, default: base.equaliser)
        browserMedia = flag(MediaSettingID.browser, default: base.browserMedia)
    }

    public func persisted() -> [String: String] {
        func bit(_ on: Bool) -> String { on ? "true" : "false" }
        return [
            MediaSettingID.follow: follow.label,
            MediaSettingID.homeMusic: homeMusic,
            MediaSettingID.playerLook: look.rawValue,
            MediaSettingID.tint: bit(tintFromSong),
            MediaSettingID.like: bit(likeFollowsSong),
            MediaSettingID.explicitBadge: bit(explicitBadge),
            MediaSettingID.explicitColour: bit(explicitMatchesColour),
            MediaSettingID.waveform: bit(waveform),
            MediaSettingID.lyrics: bit(lyrics),
            MediaSettingID.wordByWord: bit(wordByWord),
            MediaSettingID.leftButton: leftButton.rawValue,
            MediaSettingID.hideOnPause: hideOnPause.rawValue,
            MediaSettingID.openTrigger: openTrigger.rawValue,
            MediaSettingID.keepAwake: bit(keepAwake),
            MediaSettingID.equaliser: bit(equaliser),
            MediaSettingID.browser: bit(browserMedia),
        ]
    }
}

public enum MediaControlKind: Equatable, Sendable {
    case toggle(Bool)
    case choice(selected: String, options: [String])
    case status(String)
    case held(String)
}

public enum MediaControlInteraction: String, Equatable, Sendable, Hashable {
    case toggle
    case choice
    case status
    case held
}

public struct MediaControl: Equatable, Sendable, Identifiable {
    public var id: String
    public var card: String
    public var title: String
    public var helper: String
    public var accessibilityLabel: String
    public var interaction: MediaControlInteraction
    public var kind: MediaControlKind

    public init(id: String, card: String, title: String, helper: String, accessibilityLabel: String,
                interaction: MediaControlInteraction, kind: MediaControlKind) {
        self.id = id
        self.card = card
        self.title = title
        self.helper = helper
        self.accessibilityLabel = accessibilityLabel
        self.interaction = interaction
        self.kind = kind
    }
}

/// The rows of the Media page, in reading order. Every row has a helper and a VoiceOver label.
public enum MediaSectionCatalog {
    public static func controls(for settings: MediaSettings) -> [MediaControl] {
        [
            choice(MediaSettingID.follow, "Player", "Show music from",
                   "The player the notch follows. Any player shows whichever one started last.",
                   settings.follow.label, NowPlayingArbiter.Follow.choices.map(\.label)),
            choice(MediaSettingID.homeMusic, "Player", "Home music style",
                   "The home widget's music card. This does not change the player in the notch.",
                   settings.homeMusic, MediaHomeMusicStyle.choices),
            choice(MediaSettingID.playerLook, "Player", "Player look",
                   "Art, glass art, a glass card, or a detailed card. The preview follows this.",
                   settings.look.title, MediaPlayerLook.allCases.map(\.title)),
            toggle(MediaSettingID.tint, "Player", "Tint with the song",
                   "The player takes its colours from the artwork. Off keeps the usual colours.", settings.tintFromSong),
            toggle(MediaSettingID.like, "Player", "Like follows the song",
                   "The like button uses the song's colour.", settings.likeFollowsSong),
            toggle(MediaSettingID.explicitBadge, "Player", "Explicit badge",
                   "Shows a badge on a track marked explicit.", settings.explicitBadge),
            toggle(MediaSettingID.explicitColour, "Player", "Match the badge colour",
                   "The badge uses the song's colour. Off keeps it neutral.", settings.explicitMatchesColour),
            toggle(MediaSettingID.waveform, "Player", "Live waveform",
                   "A wave while music plays. It holds still when motion is reduced.", settings.waveform),
            toggle(MediaSettingID.lyrics, "Lyrics", "Synced lyrics",
                   "Looks up timed lyrics on the network. Off by default, and off sends nothing.", settings.lyrics),
            toggle(MediaSettingID.wordByWord, "Lyrics", "Word by word",
                   "Each word lights as it is sung. Off lights the whole line.", settings.wordByWord),
            status(MediaSettingID.shuffleRepeat, "Playback", "Shuffle and repeat",
                   "Repeat one stays hidden for a player that has no such mode. A script needs consent and is dropped after 3 seconds.",
                   "Two players, each with its own modes."),
            choice(MediaSettingID.leftButton, "Playback", "Left button",
                   "The button to the left of play.",
                   settings.leftButton.title, MediaLeftButton.allCases.map(\.title)),
            choice(MediaSettingID.hideOnPause, "Playback", "Hide on pause",
                   "Hide the player instantly, after a short delay, or never.",
                   settings.hideOnPause.title, MediaHidePolicy.allCases.map(\.title)),
            choice(MediaSettingID.openTrigger, "Playback", "Open the player on",
                   "Hover opens it after a pause. Click opens it only when you click.",
                   settings.openTrigger.rawValue, MediaOpenTrigger.allCases.map(\.rawValue)),
            toggle(MediaSettingID.keepAwake, "Session", "Keep the display awake",
                   "Holds the display on only while music plays. Stops on low battery or heat.", settings.keepAwake),
            toggle(MediaSettingID.equaliser, "Session", "Shape sound per app",
                   "Off by default. Off removes every tap. A denial shows a banner.", settings.equaliser),
            toggle(MediaSettingID.browser, "Session", "Media playing in the browser",
                   "Shows media from the browser extension. Off by default, and an import cannot turn it on.", settings.browserMedia),
            held(MediaSettingID.animatedArtwork, "Later", "Animated artwork"),
            held(MediaSettingID.systemNowPlaying, "Later", "Now playing across the system"),
        ]
    }

    private static func toggle(_ id: String, _ card: String, _ title: String, _ helper: String, _ on: Bool) -> MediaControl {
        row(id, card, title, helper, .toggle, .toggle(on))
    }

    private static func choice(_ id: String, _ card: String, _ title: String, _ helper: String, _ selected: String, _ options: [String]) -> MediaControl {
        row(id, card, title, helper, .choice, .choice(selected: selected, options: options))
    }

    private static func status(_ id: String, _ card: String, _ title: String, _ helper: String, _ value: String) -> MediaControl {
        row(id, card, title, helper, .status, .status(value))
    }

    private static func held(_ id: String, _ card: String, _ title: String) -> MediaControl {
        row(id, card, title, MediaHeldFeature.heldNote, .held, .held(MediaHeldFeature.heldNote))
    }

    private static func row(_ id: String, _ card: String, _ title: String, _ helper: String, _ interaction: MediaControlInteraction, _ kind: MediaControlKind) -> MediaControl {
        MediaControl(id: id, card: card, title: title, helper: helper, accessibilityLabel: "\(title). \(helper)", interaction: interaction, kind: kind)
    }
}
