import Foundation
import Testing
@testable import ZeusCore

@Suite("System source rules") struct SystemSourceRulesTests {
    private let received = Date(timeIntervalSince1970: 1_700_000_000)

    private func item(app: String = "org.videolan.vlc", parent: String = "", title: String = "Film",
                      artist: String = "Director", album: String = "Album", duration: Double = 120,
                      elapsed: Double = 10, at: Date? = nil, rate: Double = 1, key: String = "k1") -> SystemSourceRules.Item {
        SystemSourceRules.Item(app: app, parent: parent, title: title, artist: artist, album: album,
                               duration: duration, elapsed: elapsed, at: at, rate: rate, key: key)
    }

    private func verdict(_ item: SystemSourceRules.Item, browserFeedActive: Bool = false) -> SystemSourceRules.Verdict {
        SystemSourceRules.verdict(item: item, ownBundleID: SystemSourceRules.zeusBundleID, browserFeedActive: browserFeedActive)
    }

    @Test func everyVerdict() {
        #expect(verdict(item(app: "org.videolan.vlc")) == .show)
        #expect(verdict(item(app: SystemSourceRules.zeusBundleID)) == .own)
        #expect(verdict(item(app: "com.apple.FaceTime")) == .callApp)
        #expect(verdict(item(app: "com.apple.Music")) == .shadowedByPlayer)
        #expect(verdict(item(app: "com.spotify.client")) == .shadowedByPlayer)
        #expect(verdict(item(app: "com.google.Chrome"), browserFeedActive: true) == .shadowedByBrowser)
    }

    @Test func aParentBundleWinsOverTheHelpersOwn() {
        let helper = item(app: "com.example.helper", parent: SystemSourceRules.zeusBundleID)
        #expect(verdict(helper) == .own)
        #expect(verdict(item(app: "APP.ZEUS.MAC")) == .own)
        let musicHelper = item(app: "com.example.helper", parent: "com.apple.Music")
        #expect(verdict(musicHelper) == .shadowedByPlayer)
        let callHelper = item(app: "com.example.helper", parent: "com.apple.FaceTime")
        #expect(verdict(callHelper) == .callApp)
        #expect(verdict(item(app: "us.zoom.xos.helper")) == .callApp)
    }

    @Test func zeusBeatsAPlayerParentAndACallStaysACallWhileTheBrowserFeedIsOn() {
        #expect(verdict(item(app: SystemSourceRules.zeusBundleID, parent: "com.apple.Music")) == .own)
        #expect(verdict(item(app: "com.apple.FaceTime"), browserFeedActive: true) == .callApp)
        #expect(verdict(item(app: "com.tinyspeck.slackmacgap")) == .callApp)
        let empty = SystemSourceRules.verdict(item: item(app: "", parent: ""), ownBundleID: "", browserFeedActive: false)
        #expect(empty == .show)
    }

    @Test func aBrowserIsShownOnlyWhileItsFeedIsOff() {
        let chrome = item(app: "com.google.Chrome")
        #expect(verdict(chrome, browserFeedActive: false) == .show)
        #expect(verdict(chrome, browserFeedActive: true) == .shadowedByBrowser)
        let webkit = item(app: "com.apple.WebKit.WebContent")
        #expect(verdict(webkit, browserFeedActive: true) == .shadowedByBrowser)
        #expect(verdict(item(app: "com.apple.Music"), browserFeedActive: true) == .shadowedByPlayer)
    }

    @Test func aFreshServiceTimeAnchorsThePosition() {
        let at = received.addingTimeInterval(-3_600)
        let shown = SystemSourceRules.nowPlaying(item(elapsed: 15, at: at), appName: "VLC", receivedAt: received)
        #expect(shown.positionAt == at)
        #expect(shown.position == 15)
        let boundary = received.addingTimeInterval(-SystemSourceRules.positionWindow)
        let held = SystemSourceRules.nowPlaying(item(at: boundary), appName: "VLC", receivedAt: received)
        #expect(held.positionAt == boundary)
        let exact = SystemSourceRules.nowPlaying(item(at: received), appName: "VLC", receivedAt: received)
        #expect(exact.positionAt == received)
    }

    @Test func aFutureStaleOrMissingTimeUsesReceiveTime() {
        let future = SystemSourceRules.nowPlaying(item(at: received.addingTimeInterval(10)), appName: "VLC", receivedAt: received)
        #expect(future.positionAt == received)
        let staleAt = received.addingTimeInterval(-(SystemSourceRules.positionWindow + 1))
        let stale = SystemSourceRules.nowPlaying(item(at: staleAt), appName: "VLC", receivedAt: received)
        #expect(stale.positionAt == received)
        let missing = SystemSourceRules.nowPlaying(item(at: nil), appName: "VLC", receivedAt: received)
        #expect(missing.positionAt == received)
    }

    @Test func rateZeroIsPausedAndFasterRatesStayPlaying() {
        let paused = SystemSourceRules.nowPlaying(item(rate: 0), appName: "VLC", receivedAt: received)
        #expect(!paused.isPlaying)
        #expect(paused.rate == 0)
        let normal = SystemSourceRules.nowPlaying(item(rate: 1), appName: "VLC", receivedAt: received)
        #expect(normal.isPlaying)
        #expect(normal.rate == 1)
        let fast = SystemSourceRules.nowPlaying(item(rate: 2), appName: "VLC", receivedAt: received)
        #expect(fast.isPlaying)
        #expect(fast.rate == 2)
        let broken = SystemSourceRules.nowPlaying(item(duration: -4, elapsed: .nan, rate: .infinity), appName: "VLC", receivedAt: received)
        #expect(!broken.isPlaying)
        #expect(broken.rate == 0)
        #expect(broken.position == 0)
        #expect(broken.duration == 0)
    }

    @Test func liveContentHasNoSeekAndNeverOffersLyrics() {
        for duration in [0.0, -1, Double.nan] {
            let live = SystemSourceRules.nowPlaying(item(artist: "Band", duration: duration), appName: "VLC", receivedAt: received)
            #expect(!live.capabilities.contains(.seek))
            #expect(!live.capabilities.contains(.lyrics))
            #expect(!live.capabilities.contains(.shuffle))
            #expect(!live.capabilities.contains(.repeatMode))
            #expect(live.capabilities.contains(.playPause))
            #expect(live.capabilities.contains(.next))
            #expect(live.capabilities.contains(.previous))
        }
        let recorded = SystemSourceRules.nowPlaying(item(duration: 90), appName: "VLC", receivedAt: received)
        #expect(recorded.capabilities == [.playPause, .next, .previous, .seek])
        #expect(!recorded.capabilities.contains(.lyrics))
    }

    @Test func anEmptyAppNameReadsThisMac() {
        #expect(SystemSourceRules.nowPlaying(item(), appName: "", receivedAt: received).appName == "This Mac")
        #expect(SystemSourceRules.nowPlaying(item(), appName: "   ", receivedAt: received).appName == "This Mac")
        let named = SystemSourceRules.nowPlaying(item(app: "org.videolan.vlc", key: "k9"), appName: "VLC", receivedAt: received)
        #expect(named.appName == "VLC")
        #expect(named.appBundleID == "org.videolan.vlc")
        #expect(named.key == "k9")
        #expect(named.title == "Film")
    }

    @Test func positionOnlyUpdatesPassInsideTheSecond() {
        let previous = item(elapsed: 10)
        let moved = item(elapsed: 11, rate: 1)
        let now = received
        #expect(SystemSourceRules.forward(previous: previous, next: moved, lastIdentityChange: now, now: now.addingTimeInterval(0.2)))
        let album = item(album: "Other")
        #expect(SystemSourceRules.forward(previous: previous, next: album, lastIdentityChange: now, now: now))
    }

    @Test func anIdentityBurstKeepsTheFirstChange() {
        let first = item(title: "One")
        let second = item(title: "Two")
        let third = item(title: "Three")
        let start = received
        #expect(SystemSourceRules.forward(previous: nil, next: first, lastIdentityChange: start.addingTimeInterval(-10), now: start))
        #expect(!SystemSourceRules.forward(previous: first, next: second, lastIdentityChange: start, now: start.addingTimeInterval(0.4)))
        #expect(SystemSourceRules.forward(previous: second, next: third, lastIdentityChange: start, now: start.addingTimeInterval(1)))
        let artist = item(artist: "Other")
        #expect(!SystemSourceRules.forward(previous: first, next: artist, lastIdentityChange: start, now: start))
        let app = item(app: "com.example.other")
        #expect(!SystemSourceRules.forward(previous: first, next: app, lastIdentityChange: start, now: start.addingTimeInterval(0.9)))
    }

    @Test func everySlotChange() {
        let key = "k1"
        #expect(SystemSourceRules.slot(verdict: nil, key: key, current: key) == .clear)
        for verdict: SystemSourceRules.Verdict in [.own, .callApp, .shadowedByPlayer, .shadowedByBrowser] {
            #expect(SystemSourceRules.slot(verdict: verdict, key: key, current: key) == .clear)
        }
        #expect(SystemSourceRules.slot(verdict: .show, key: key, current: nil) == .replace)
        #expect(SystemSourceRules.slot(verdict: .show, key: "k2", current: key) == .replace)
        #expect(SystemSourceRules.slot(verdict: .show, key: key, current: key) == .update)
    }

    @Test func playPauseFollowsTheRate() {
        let playing = item(rate: 1, key: "shown")
        let paused = item(rate: 0, key: "shown")
        #expect(SystemSourceRules.command(for: .playPause, item: playing, seconds: 4, key: "shown")?.name == .pause)
        #expect(SystemSourceRules.command(for: .playPause, item: paused, seconds: 4, key: "shown")?.name == .play)
        #expect(SystemSourceRules.command(for: .playPause, item: item(rate: -1, key: "shown"), seconds: 0, key: "shown")?.name == .play)
        #expect(SystemSourceRules.command(for: .play, item: paused, seconds: 9, key: "shown") == .init(name: .play, seconds: 0, app: paused.app))
        #expect(SystemSourceRules.command(for: .pause, item: playing, seconds: 9, key: "shown")?.name == .pause)
        #expect(SystemSourceRules.command(for: .next, item: playing, seconds: 9, key: "shown")?.name == .next)
        #expect(SystemSourceRules.command(for: .previous, item: playing, seconds: 9, key: "shown")?.name == .previous)
    }

    @Test func shuffleRepeatOpenAndAStaleKeySendNothing() {
        let playing = item(key: "shown")
        for kind: MusicCommandKind in [.toggleShuffle, .cycleRepeat, .open] {
            #expect(SystemSourceRules.command(for: kind, item: playing, seconds: 1, key: "shown") == nil)
        }
        #expect(SystemSourceRules.command(for: .play, item: playing, seconds: 0, key: "other") == nil)
        #expect(SystemSourceRules.command(for: .play, item: playing, seconds: 0, key: "") == nil)
        #expect(SystemSourceRules.command(for: .play, item: item(key: ""), seconds: 0, key: "shown") == nil)
    }

    @Test func seekClampsABadPositionAndRefusesLiveContent() {
        let playing = item(duration: 120, key: "shown")
        #expect(SystemSourceRules.command(for: .seek, item: playing, seconds: 12.5, key: "shown") == .init(name: .seek, seconds: 12.5, app: playing.app))
        #expect(SystemSourceRules.command(for: .seek, item: playing, seconds: -4, key: "shown")?.seconds == 0)
        #expect(SystemSourceRules.command(for: .seek, item: playing, seconds: .nan, key: "shown")?.seconds == 0)
        #expect(SystemSourceRules.command(for: .seek, item: playing, seconds: .infinity, key: "shown")?.seconds == 0)
        #expect(SystemSourceRules.command(for: .seek, item: item(duration: 0, key: "shown"), seconds: 3, key: "shown") == nil)
        #expect(SystemSourceRules.command(for: .seek, item: item(duration: .nan, key: "shown"), seconds: 3, key: "shown") == nil)
    }
}
