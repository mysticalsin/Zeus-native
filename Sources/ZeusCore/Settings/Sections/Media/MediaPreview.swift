import Foundation

/// A sample track for the settings preview. It never leaves the page and it never uses the network.
public struct MediaPreviewSample: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var explicit: Bool
    public var rgba: [UInt8]
    public var levels: [Double]
    public var lyric: String
    public var lyricStart: Double
    public var lyricEnd: Double
    public var position: Double
    public var duration: Double
    public var player: NowPlaying.Player
    public var capabilities: SourceCapabilities
    public var isPlaying: Bool

    public init(title: String, artist: String, album: String, explicit: Bool, rgba: [UInt8], levels: [Double], lyric: String,
                lyricStart: Double, lyricEnd: Double, position: Double, duration: Double, player: NowPlaying.Player, capabilities: SourceCapabilities, isPlaying: Bool) {
        self.title = title
        self.artist = artist
        self.album = album
        self.explicit = explicit
        self.rgba = rgba
        self.levels = levels
        self.lyric = lyric
        self.lyricStart = lyricStart
        self.lyricEnd = lyricEnd
        self.position = position
        self.duration = duration
        self.player = player
        self.capabilities = capabilities
        self.isPlaying = isPlaying
    }

    public static let demo = MediaPreviewSample(
        title: "Night Drive",
        artist: "Sample",
        album: "Preview",
        explicit: true,
        rgba: Array(repeating: [UInt8(210), 28, 36, 255], count: 24).flatMap { $0 },
        levels: [0.2, 0.6, 0.9],
        lyric: "city lights on the water",
        lyricStart: 10,
        lyricEnd: 14,
        position: 72,
        duration: 220,
        player: NowPlaying.Player.allCases[0],
        capabilities: [.playPause, .previous, .next, .shuffle, .repeatMode, .lyrics],
        isPlaying: true
    )
}

public enum MediaPreviewPhase: Equatable, Sendable {
    case loading
    case empty
    case failed(String)
    case ready(MediaPreviewSample)
}

/// The player card the Media page draws. It follows the saved look and does not restyle the notch.
public struct MediaPreview: Equatable, Sendable {
    public var look: MediaPlayerLook
    public var title: String
    public var artist: String
    public var album: String
    public var visible: Bool
    public var canResume: Bool
    public var showsArt: Bool
    public var glass: Bool
    public var showsDetail: Bool
    public var solidFallback: Bool
    public var palette: MediaSongPalette
    public var like: ArtworkColor.RGB
    public var badge: String?
    public var badgeColor: ArtworkColor.RGB
    public var waveform: MediaWaveform?
    public var lyric: MediaLyricHighlight
    public var left: MediaLeftButtonPlan
    public var repeatModes: [RepeatMode]
    public var offersRepeatOne: Bool
    public var animationDuration: TimeInterval
    public var statusTitle: String
    public var detailLine: String
    public var accessibilityLabel: String

    public init(look: MediaPlayerLook, title: String, artist: String, album: String, visible: Bool, canResume: Bool,
                showsArt: Bool, glass: Bool, showsDetail: Bool, solidFallback: Bool, palette: MediaSongPalette,
                like: ArtworkColor.RGB, badge: String?, badgeColor: ArtworkColor.RGB, waveform: MediaWaveform?,
                lyric: MediaLyricHighlight, left: MediaLeftButtonPlan, repeatModes: [RepeatMode], offersRepeatOne: Bool,
                animationDuration: TimeInterval, statusTitle: String, detailLine: String, accessibilityLabel: String) {
        self.look = look
        self.title = title
        self.artist = artist
        self.album = album
        self.visible = visible
        self.canResume = canResume
        self.showsArt = showsArt
        self.glass = glass
        self.showsDetail = showsDetail
        self.solidFallback = solidFallback
        self.palette = palette
        self.like = like
        self.badge = badge
        self.badgeColor = badgeColor
        self.waveform = waveform
        self.lyric = lyric
        self.left = left
        self.repeatModes = repeatModes
        self.offersRepeatOne = offersRepeatOne
        self.animationDuration = animationDuration
        self.statusTitle = statusTitle
        self.detailLine = detailLine
        self.accessibilityLabel = accessibilityLabel
    }
}

public enum MediaPreviewBuilder {
    public static func make(settings: MediaSettings, phase: MediaPreviewPhase, hide: MediaHideMachine,
                            access: GlassSettingsAccess, lyricsPhase: MediaLyricPhase) -> MediaPreview {
        let material = GlassSettingsMaterialRules.resolve(access)
        let sample: MediaPreviewSample? = {
            if case .ready(let sample) = phase { return sample }
            return nil
        }()
        let ready = sample != nil
        let concealed = ready && hide.state == .hidden
        let palette = settings.tintFromSong ? MediaSongPalette.extract(rgba: sample?.rgba ?? []) : .neutral
        let status = statusTitle(phase: phase, concealed: concealed)
        let lyricLine = LyricLine(time: sample?.lyricStart ?? 0, text: sample?.lyric ?? "")
        let lineEnd = sample?.lyricEnd ?? lyricLine.time
        let words = LyricWordTiming.words(in: lyricLine, lineEnd: lineEnd)
        let lyricTime = words.count > 1 ? words[1].start + 0.01 : lyricLine.time
        let lyric = MediaLyricPreview.highlight(
            enabled: settings.lyrics, wordByWord: settings.wordByWord, phase: lyricsPhase, line: lyricLine,
            lineEnd: lineEnd, time: lyricTime
        )
        let modes = sample.map { MusicModeRules.supportedRepeatModes($0.player) } ?? []
        let look = settings.look
        return MediaPreview(
            look: look,
            title: sample?.title ?? "",
            artist: sample?.artist ?? "",
            album: look.showsDetail ? (sample?.album ?? "") : "",
            visible: ready && !concealed,
            canResume: ready,
            showsArt: look.showsArt,
            glass: look.usesGlass && !material.solidFallback,
            showsDetail: look.showsDetail,
            solidFallback: material.solidFallback,
            palette: palette,
            like: palette.like(followsSong: settings.likeFollowsSong),
            badge: (sample?.explicit == true && settings.explicitBadge) ? "Explicit" : nil,
            badgeColor: palette.badge(matchColour: settings.explicitMatchesColour),
            waveform: ready ? MediaWaveform.make(levels: sample?.levels ?? [], enabled: settings.waveform, reduceMotion: access.reduceMotion) : nil,
            lyric: lyric,
            left: MediaLeftButtonRules.plan(choice: settings.leftButton, capabilities: sample?.capabilities ?? [], lyricsOn: settings.lyrics),
            repeatModes: modes,
            offersRepeatOne: modes.contains(.one),
            animationDuration: material.animationDuration,
            statusTitle: status,
            detailLine: look.showsDetail ? Self.clock(sample) : "",
            accessibilityLabel: "\(look.title) player. \(status)"
        )
    }

    private static func clock(_ sample: MediaPreviewSample?) -> String {
        guard let sample, sample.duration > 0 else { return "" }
        return "\(stamp(sample.position)) / \(stamp(sample.duration))"
    }

    private static func stamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func statusTitle(phase: MediaPreviewPhase, concealed: Bool) -> String {
        if concealed { return "Hidden while paused" }
        switch phase {
        case .loading: return "Loading the player"
        case .empty: return "Nothing playing"
        case .failed(let message): return message
        case .ready(let sample): return sample.title
        }
    }
}
