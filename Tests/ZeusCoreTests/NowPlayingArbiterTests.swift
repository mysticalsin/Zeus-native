import Foundation
import Testing
@testable import ZeusCore

@Suite struct NowPlayingArbiterTests {
    private static let music = NowPlayingSource.player(.music)
    private static let spotify = NowPlayingSource.player(.spotify)
    private static func tab(_ id: Int) -> NowPlayingSource {
        .browser(BrowserMediaKey(tabID: id, documentID: "doc-\(id)", host: "example.com", fingerprint: "f\(id)"))
    }

    private static let base = Date(timeIntervalSince1970: 1_000)
    private func at(_ seconds: Double) -> Date { Self.base.addingTimeInterval(seconds) }

    private func item(_ source: NowPlayingSource, _ title: String = "Song", playing: Bool = true) -> NowPlaying {
        NowPlaying(source: source, title: title, artist: "Band", album: "Record", isPlaying: playing, duration: 200, position: 0)
    }

    private func shown(_ arbiter: NowPlayingArbiter, _ follow: NowPlayingArbiter.Follow = .any) -> NowPlayingSource? {
        arbiter.shown(follow: follow)?.playing.source
    }

    // MARK: What is shown

    @Test func aSecondStartWins() {
        var arbiter = NowPlayingArbiter()
        arbiter.update(Self.music, item(Self.music), now: at(0))
        #expect(shown(arbiter) == Self.music)
        arbiter.update(Self.spotify, item(Self.spotify), now: at(10))
        #expect(shown(arbiter) == Self.spotify)
        arbiter.update(Self.tab(4), item(Self.tab(4)), now: at(20))
        #expect(shown(arbiter) == Self.tab(4))
    }

    @Test func theShownSourcePausingWhileAnotherPlaysShowsTheOneThatPlays() {
        var arbiter = NowPlayingArbiter()
        arbiter.update(Self.music, item(Self.music), now: at(0))
        arbiter.update(Self.spotify, item(Self.spotify), now: at(10))
        arbiter.update(Self.spotify, item(Self.spotify, playing: false), now: at(20))
        #expect(shown(arbiter) == Self.music)
        #expect(arbiter.shown(follow: .any)?.playing.isPlaying == true)
    }

    @Test func pausingAloneStaysShownPaused() {
        var arbiter = NowPlayingArbiter()
        arbiter.update(Self.music, item(Self.music), now: at(0))
        arbiter.update(Self.music, item(Self.music, playing: false), now: at(30))
        #expect(shown(arbiter) == Self.music)
        #expect(arbiter.shown(follow: .any)?.playing.isPlaying == false)
    }

    @Test func whenNothingPlaysTheLastOneThatStartedStays() {
        var arbiter = NowPlayingArbiter()
        arbiter.update(Self.music, item(Self.music), now: at(0))
        arbiter.update(Self.spotify, item(Self.spotify), now: at(10))
        arbiter.update(Self.music, item(Self.music, playing: false), now: at(20))
        arbiter.update(Self.spotify, item(Self.spotify, playing: false), now: at(30))
        #expect(shown(arbiter) == Self.spotify)
    }

    @Test func aSourceFirstSeenPausedNeverDisplacesTheShownOne() {
        var arbiter = NowPlayingArbiter()
        arbiter.update(Self.music, item(Self.music), now: at(0))
        arbiter.update(Self.spotify, item(Self.spotify, playing: false), now: at(5))
        #expect(shown(arbiter) == Self.music)
        // Also while nothing plays: the one that started stays over one never heard.
        arbiter.update(Self.music, item(Self.music, playing: false), now: at(10))
        #expect(shown(arbiter) == Self.music)
        arbiter.update(Self.tab(2), item(Self.tab(2), playing: false), now: at(12))
        #expect(shown(arbiter) == Self.music)
    }

    @Test func amongSourcesThatNeverStartedTheLatestSeenIsShown() {
        var arbiter = NowPlayingArbiter()
        arbiter.update(Self.spotify, item(Self.spotify, playing: false), now: at(0))
        arbiter.update(Self.music, item(Self.music, playing: false), now: at(5))
        #expect(shown(arbiter) == Self.music)
        arbiter.update(Self.spotify, item(Self.spotify, "Other", playing: false), now: at(9))
        #expect(shown(arbiter) == Self.spotify)
    }

    @Test func aPausedSourceThatStartsAgainTakesTheStartOver() {
        var arbiter = NowPlayingArbiter()
        arbiter.update(Self.music, item(Self.music), now: at(0))
        arbiter.update(Self.spotify, item(Self.spotify), now: at(10))
        arbiter.update(Self.music, item(Self.music, playing: false), now: at(15))
        arbiter.update(Self.music, item(Self.music), now: at(20))
        #expect(shown(arbiter) == Self.music)
        #expect(arbiter.entry(Self.music)?.startedAt == at(20))
    }

    @Test func aTrackChangeKeepsTheStart() {
        var arbiter = NowPlayingArbiter()
        arbiter.update(Self.music, item(Self.music, "One"), now: at(0))
        arbiter.update(Self.spotify, item(Self.spotify), now: at(5))
        arbiter.update(Self.music, item(Self.music, "Two"), now: at(10))
        #expect(arbiter.entry(Self.music)?.startedAt == at(0))
        #expect(arbiter.entry(Self.music)?.seenAt == at(10))
        #expect(arbiter.entry(Self.music)?.playing.title == "Two")
        #expect(shown(arbiter) == Self.spotify)
    }

    @Test func aSampleOfAnEntryUpdatesWhatWasSeenButNotWhenItStarted() {
        var arbiter = NowPlayingArbiter()
        arbiter.update(Self.music, item(Self.music), now: at(0))
        arbiter.update(Self.music, item(Self.music), now: at(50))
        #expect(arbiter.entry(Self.music)?.startedAt == at(0))
        #expect(arbiter.entry(Self.music)?.seenAt == at(50))
    }

    // MARK: Leaving

    @Test func nilRemovesTheEntry() {
        var arbiter = NowPlayingArbiter()
        arbiter.update(Self.music, item(Self.music), now: at(0))
        arbiter.update(Self.spotify, item(Self.spotify), now: at(5))
        #expect(arbiter.update(Self.spotify, nil, now: at(6)))
        #expect(arbiter.entry(Self.spotify) == nil)
        #expect(shown(arbiter) == Self.music)
        arbiter.update(Self.music, nil, now: at(7))
        #expect(arbiter.shown(follow: .any) == nil)
    }

    @Test func removeWhereDropsEveryMatch() {
        var arbiter = NowPlayingArbiter()
        arbiter.update(Self.music, item(Self.music), now: at(0))
        arbiter.update(Self.tab(1), item(Self.tab(1)), now: at(1))
        arbiter.update(Self.tab(2), item(Self.tab(2)), now: at(2))
        arbiter.remove { source in
            if case .browser = source { return true }
            return false
        }
        #expect(arbiter.entry(Self.tab(1)) == nil && arbiter.entry(Self.tab(2)) == nil)
        #expect(shown(arbiter) == Self.music)
        arbiter.remove { _ in true }
        #expect(arbiter.shown(follow: .any) == nil)
    }

    // MARK: Pins

    @Test func aPinShowsOnlyThatPlayer() {
        var arbiter = NowPlayingArbiter()
        arbiter.update(Self.music, item(Self.music), now: at(0))
        arbiter.update(Self.spotify, item(Self.spotify), now: at(10))
        arbiter.update(Self.tab(3), item(Self.tab(3)), now: at(20))
        #expect(shown(arbiter, .pinned(.music)) == Self.music)
        #expect(shown(arbiter, .pinned(.spotify)) == Self.spotify)
        // A pinned player that is paused is still shown, paused, while another source plays.
        arbiter.update(Self.music, item(Self.music, playing: false), now: at(25))
        #expect(shown(arbiter, .pinned(.music)) == Self.music)
        #expect(arbiter.shown(follow: .pinned(.music))?.playing.isPlaying == false)
    }

    @Test func aPinnedPlayerThatIsAbsentShowsNothing() {
        var arbiter = NowPlayingArbiter()
        arbiter.update(Self.music, item(Self.music), now: at(0))
        arbiter.update(Self.tab(3), item(Self.tab(3)), now: at(5))
        #expect(arbiter.shown(follow: .pinned(.spotify)) == nil)
        #expect(NowPlayingArbiter().shown(follow: .pinned(.music)) == nil)
    }

    // MARK: Ties

    @Test func tiesGoToMusicThenSpotifyThenBrowserByTabID() {
        var arbiter = NowPlayingArbiter()
        for source in [Self.tab(9), Self.tab(3), Self.spotify, Self.music] {
            arbiter.update(source, item(source), now: at(0))
        }
        #expect(shown(arbiter) == Self.music)
        arbiter.remove { $0 == Self.music }
        #expect(shown(arbiter) == Self.spotify)
        arbiter.remove { $0 == Self.spotify }
        #expect(shown(arbiter) == Self.tab(3))
        arbiter.remove { $0 == Self.tab(3) }
        #expect(shown(arbiter) == Self.tab(9))
    }

    @Test func tiesAmongPausedEntriesFollowTheSameOrder() {
        var arbiter = NowPlayingArbiter()
        for source in [Self.tab(2), Self.spotify, Self.music] {
            arbiter.update(source, item(source, playing: false), now: at(0))
        }
        #expect(shown(arbiter) == Self.music)
    }

    // MARK: Labels and targets

    @Test func labelsMapToAFollowAndUnknownMeansAny() {
        #expect(NowPlayingArbiter.Follow(label: "Any player") == .any)
        #expect(NowPlayingArbiter.Follow(label: "Music") == .pinned(.music))
        #expect(NowPlayingArbiter.Follow(label: "Spotify") == .pinned(.spotify))
        for unknown in ["", "Chrome", "music", "Any", "Spotify "] as [String?] {
            #expect(NowPlayingArbiter.Follow(label: unknown) == .any)
        }
        #expect(NowPlayingArbiter.Follow(label: nil) == .any)
        for follow in [NowPlayingArbiter.Follow.any, .pinned(.music), .pinned(.spotify)] {
            #expect(NowPlayingArbiter.Follow(label: follow.label) == follow)
        }
        #expect(NowPlayingArbiter.Follow.any.label == "Any player")
    }

    @Test func theCommandTargetIsTheShownSourceElseThePinElseMusic() {
        let arbiter = NowPlayingArbiter()
        #expect(arbiter.commandTarget(shown: Self.tab(1), follow: .any) == Self.tab(1))
        #expect(arbiter.commandTarget(shown: Self.spotify, follow: .pinned(.music)) == Self.spotify)
        #expect(arbiter.commandTarget(shown: nil, follow: .pinned(.spotify)) == Self.spotify)
        #expect(arbiter.commandTarget(shown: nil, follow: .pinned(.music)) == Self.music)
        #expect(arbiter.commandTarget(shown: nil, follow: .any) == Self.music)
    }

    // MARK: Mismatch and sessions

    @Test func aMismatchedUpdateIsRejectedWithNoChange() {
        var arbiter = NowPlayingArbiter()
        #expect(!arbiter.update(Self.music, item(Self.spotify), now: at(0)))
        #expect(arbiter.entry(Self.music) == nil && arbiter.entry(Self.spotify) == nil)
        #expect(arbiter.update(Self.music, item(Self.music), now: at(1)))
        let before = arbiter
        #expect(!arbiter.update(Self.music, item(Self.tab(1), "Other"), now: at(2)))
        #expect(arbiter == before)
    }

    @Test func aBrowserTabIsNotAPlayerSession() {
        var arbiter = NowPlayingArbiter()
        #expect(!arbiter.hasPlayerSession)
        arbiter.update(Self.tab(1), item(Self.tab(1)), now: at(0))
        #expect(!arbiter.hasPlayerSession)
        arbiter.update(Self.spotify, item(Self.spotify, playing: false), now: at(1))
        #expect(arbiter.hasPlayerSession)
        arbiter.update(Self.spotify, nil, now: at(2))
        #expect(!arbiter.hasPlayerSession)
        arbiter.update(Self.music, item(Self.music), now: at(3))
        #expect(arbiter.hasPlayerSession)
    }
}
