import Foundation
import Testing
@testable import ZeusCore

@Suite struct LockContentTests {
    private let now = Date(timeIntervalSince1970: 1_764_000_000)

    private func player(title: String = "Kind of Blue", artist: String = "Miles Davis", hue: Double = 0.42,
                        isPlaying: Bool = true, duration: Double = 200, position: Double = 12,
                        canControl: Bool = true, running: Bool = true,
                        kind: LockTrackKind = .player) -> LockTrack {
        LockTrack(kind: kind, playerRunning: running, title: title, artist: artist, hue: hue,
                  isPlaying: isPlaying, duration: duration, position: position,
                  positionAt: now.addingTimeInterval(-5), canControl: canControl)
    }

    private func options(showTrackDetails: Bool = true, hideDetails: Bool = false, lyrics: Bool = false,
                         lyricsPrivacy: Bool = false, clock: Bool = false) -> LockOptions {
        LockOptions(showTrackDetails: showTrackDetails, hideDetails: hideDetails, lyrics: lyrics,
                    lyricsPrivacy: lyricsPrivacy, clock: clock)
    }

    private func scene(_ track: LockTrack?, _ options: LockOptions, lyrics: LockLyrics? = nil,
                       at now: Date? = nil) -> LockScene {
        LockContentPolicy.scene(track: track, options: options, lyricLine: lyrics, at: now ?? self.now)
    }

    @Test func aRunningPlayerShowsTheFullCard() {
        let cardScene = scene(player(), options())
        guard case .full(let title, let artist, let hue, let isPlaying, let progress, let lyric, let controls) = cardScene.card else {
            Issue.record("Expected a full card")
            return
        }
        #expect(title == "Kind of Blue")
        #expect(artist == "Miles Davis")
        #expect(hue == 0.42)
        #expect(isPlaying)
        #expect(progress.elapsed == 17)
        #expect(progress.duration == 200)
        #expect(lyric == nil)
        #expect(controls == .transport)
        #expect(!cardScene.showsClock)
        #expect(!cardScene.isEmpty)
    }

    @Test(arguments: [
        "show track details off",
        "privacy details off",
        "meeting mode on",
    ])
    func eachHideSwitchGivesTheQuietCard(which: String) {
        let hiding: LockOptions
        switch which {
        case "show track details off":
            hiding = options(showTrackDetails: false)
        case "privacy details off", "meeting mode on":
            hiding = options(hideDetails: true, lyrics: true, lyricsPrivacy: true)
        default:
            Issue.record("Unknown switch \(which)")
            return
        }
        let lyrics = LockLyrics.synced([LockLyricLine(time: 0, text: "secret lyric")])
        let cardScene = scene(player(title: "SECRET-TITLE", artist: "SECRET-ARTIST", hue: 0.42), hiding, lyrics: lyrics)
        guard case .quiet(let isPlaying, let controls) = cardScene.card else {
            Issue.record("Expected a quiet card for \(which)")
            return
        }
        #expect(isPlaying)
        #expect(controls == .transport)
        let text = String(describing: cardScene)
        #expect(!text.contains("SECRET-TITLE"))
        #expect(!text.contains("SECRET-ARTIST"))
        #expect(!text.contains("secret lyric"))
        #expect(!text.contains("0.42"))
        #expect(!text.contains("progress"))
    }

    @Test func aBrowserTrackAndAStoppedPlayerDrawNoCard() {
        let browser = scene(player(kind: .other), options())
        #expect(browser.card == nil)
        #expect(browser.isEmpty)
        #expect(!String(describing: browser).contains("Kind of Blue"))

        let stopped = scene(player(running: false), options())
        #expect(stopped.card == nil)
        #expect(stopped.isEmpty)

        let absent = scene(nil, options())
        #expect(absent.card == nil)
        #expect(absent.isEmpty)
    }

    @Test func noControlsWithoutPermissionAndThenNoQuietCard() {
        let full = scene(player(canControl: false), options())
        guard case .full(_, _, _, _, _, _, let controls) = full.card else {
            Issue.record("Expected a full card without buttons")
            return
        }
        #expect(controls.isEmpty)
        #expect(!LockCommandPolicy.allows(.playPause, scene: full, mayShow: true))

        let quiet = scene(player(canControl: false), options(hideDetails: true))
        #expect(quiet.card == nil)
        #expect(quiet.isEmpty)
    }

    @Test func aLyricNeedsBothSwitchesAndASyncedLine() {
        let lines = LockLyrics.synced([
            LockLyricLine(time: 0, text: "first"),
            LockLyricLine(time: 10, text: "second line"),
        ])
        let shown = scene(player(), options(lyrics: true, lyricsPrivacy: true), lyrics: lines)
        guard case .full(_, _, _, _, _, let lyric, _) = shown.card else {
            Issue.record("Expected a full card")
            return
        }
        #expect(lyric == "second line")

        for blocked in [
            options(lyrics: false, lyricsPrivacy: true),
            options(lyrics: true, lyricsPrivacy: false),
        ] {
            let hidden = scene(player(), blocked, lyrics: lines)
            guard case .full(_, _, _, _, _, let line, _) = hidden.card else {
                Issue.record("Expected a full card")
                return
            }
            #expect(line == nil)
        }

        for lyrics in [LockLyrics.plain("plain secret"), .instrumental, .none] as [LockLyrics] {
            let refused = scene(player(), options(lyrics: true, lyricsPrivacy: true), lyrics: lyrics)
            guard case .full(_, _, _, _, _, let line, _) = refused.card else {
                Issue.record("Expected a full card")
                return
            }
            #expect(line == nil)
            #expect(!String(describing: refused).contains("plain secret"))
        }

        #expect(LockLyric.line(lines, elapsed: 3) == "first")
        #expect(LockLyric.line(lines, elapsed: -1) == nil)
    }

    @Test func theClockRowCanStandAlone() {
        let alone = scene(nil, options(clock: true))
        #expect(alone.card == nil)
        #expect(alone.showsClock)
        #expect(!alone.isEmpty)

        let withCard = scene(player(), options(clock: true))
        #expect(withCard.card != nil)
        #expect(withCard.showsClock)
        #expect(!withCard.isEmpty)

        let neither = scene(nil, options(clock: false))
        #expect(neither.isEmpty)
    }

    @Test func cleaningRemovesMarksAndCutsAtTheLimit() {
        #expect(LockText.clean("Hello\nWorld", limit: 80) == "HelloWorld")
        #expect(LockText.clean("Hello\u{202E}World", limit: 80) == "HelloWorld")
        #expect(LockText.clean("Hello\u{200D}World", limit: 80) == "HelloWorld")
        #expect(LockText.clean("A   B\tC", limit: 80) == "A B C")
        #expect(LockText.clean(" \n\u{200B} ", limit: 80) == nil)
        #expect(LockText.clean(String(repeating: "a", count: 90), limit: 80)?.count == 80)
        #expect(LockText.clean(String(repeating: "b", count: 90), limit: LockText.titleLimit)?.count == LockText.titleLimit)
        #expect(LockText.clean(String(repeating: "c", count: 90), limit: LockText.artistLimit)?.count == LockText.artistLimit)
        #expect(LockText.clean(String(repeating: "d", count: 200), limit: LockText.lyricLimit)?.count == LockText.lyricLimit)
    }

    @Test func commandsFollowTheDrawnButtonsAndTheSession() {
        let shown = scene(player(), options())
        #expect(LockCommandPolicy.allows(.previous, scene: shown, mayShow: true))
        #expect(LockCommandPolicy.allows(.playPause, scene: shown, mayShow: true))
        #expect(LockCommandPolicy.allows(.next, scene: shown, mayShow: true))
        #expect(!LockCommandPolicy.allows(.playPause, scene: shown, mayShow: false))
        #expect(!LockCommandPolicy.allows(.next, scene: shown, mayShow: false))
        #expect(!LockCommandPolicy.allows(.previous, scene: shown, mayShow: false))

        let undrawn = scene(player(canControl: false), options())
        #expect(!LockCommandPolicy.allows(.playPause, scene: undrawn, mayShow: true))
        #expect(!LockCommandPolicy.allows(.next, scene: undrawn, mayShow: true))
        #expect(!LockCommandPolicy.allows(.previous, scene: undrawn, mayShow: true))

        let empty = scene(nil, options())
        #expect(!LockCommandPolicy.allows(.playPause, scene: empty, mayShow: true))
    }

    @Test func clockStringsUseTheLocaleHourCycleAndNoDash() {
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(secondsFromGMT: 0) else {
            Issue.record("Expected UTC")
            return
        }
        calendar.timeZone = zone
        // 2026-11-25 15:04 UTC.
        let date = Date(timeIntervalSince1970: 1_795_619_040)
        let twelve = LockClock.time(date, calendar: calendar, locale: Locale(identifier: "en_US"))
        let twentyFour = LockClock.time(date, calendar: calendar, locale: Locale(identifier: "en_GB"))
        #expect(twelve.contains("3:04"))
        #expect(twelve.contains("PM"))
        #expect(!twelve.contains("15"))
        #expect(twentyFour == "15:04")
        let day = LockClock.day(date, calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(day.contains("25"))
        for text in [twelve, twentyFour, day, LockSpoken.card(scene(player(isPlaying: false), options()))] {
            #expect(!text.contains("\u{2014}"))
            #expect(!text.contains("\u{2013}"))
        }
    }

    @Test func spokenLinesNameTheTrackOnlyWhenPausedAndNeverAPlayer() {
        let playing = scene(player(), options())
        #expect(LockSpoken.card(playing) == "Playing")
        let paused = scene(player(isPlaying: false), options())
        #expect(LockSpoken.card(paused) == "Kind of Blue, Miles Davis, paused")
        let quiet = scene(player(isPlaying: false), options(hideDetails: true))
        #expect(LockSpoken.card(quiet) == "Paused")
        #expect(!LockSpoken.card(paused).contains("Spotify"))
        #expect(!LockSpoken.card(paused).contains("Music"))
        let times = LockProgress.times(elapsed: 17, duration: 200)
        #expect(times.elapsed == "0:17")
        #expect(times.remaining == "3:03")
    }

    @Test func aPauseHoldsPositionAndAnEmptyPauseDrawsNothing() {
        let held = player(isPlaying: false, position: 12)
        #expect(held.elapsed(at: now.addingTimeInterval(30)) == 12)
        let idle = scene(player(title: " \n ", artist: "", isPlaying: false), options())
        #expect(idle.card == nil)
    }
}
