import Foundation
import Observation
import Testing
import ZeusCore
@testable import Zeus

/// The hub with recording closures for every effect: no player, no browser, no Apple Event, no artwork fetch.
@MainActor private final class Rig {
    let model: TopBarModel
    let hub: NowPlayingHub
    let music = NowPlayingSource.player(.music)
    let spotify = NowPlayingSource.player(.spotify)
    var label: String?
    var clock = Date(timeIntervalSince1970: 50_000)
    /// What the player side answers when asked to send: false stands for "not running" or "no Automation".
    var playerAccepts = true
    var sent: [(player: NowPlaying.Player, kind: MusicCommandKind)] = []
    var seeks: [(player: NowPlaying.Player, seconds: Double)] = []
    var readBacks: [NowPlaying.Player] = []
    var modeReads: [NowPlaying.Player] = []
    var modeResets = 0
    var opened: [NowPlayingSource] = []
    var cues: [NotchCue] = []
    var covers: [NowPlaying?] = []
    var browser: [(kind: MusicCommandKind, seconds: Double?, key: BrowserMediaKey)] = []

    init() {
        model = TopBarModel(defaults: UserDefaults(suiteName: "NowPlayingHubTests.\(UUID().uuidString)") ?? .standard)
        hub = NowPlayingHub(model: model)
        hub.ports.follow = { [unowned self] in label }
        hub.ports.now = { [unowned self] in clock }
        hub.ports.sendToPlayer = { [unowned self] player, kind in
            sent.append((player, kind))
            return playerAccepts
        }
        hub.ports.seekPlayer = { [unowned self] player, seconds in
            seeks.append((player, seconds))
            return playerAccepts
        }
        hub.ports.readBack = { [unowned self] in readBacks.append($0) }
        hub.ports.readModes = { [unowned self] in modeReads.append($0) }
        hub.ports.resetModes = { [unowned self] in modeResets += 1 }
        hub.ports.open = { [unowned self] in opened.append($0) }
        hub.ports.showCue = { [unowned self] in cues.append($0) }
        hub.ports.requestArtwork = { [unowned self] in covers.append($0) }
        hub.attach()
    }

    func enableBrowser() {
        hub.browserCommand = { [unowned self] kind, seconds, key in browser.append((kind, seconds, key)) }
    }

    func advance(_ seconds: Double = 1) { clock = clock.addingTimeInterval(seconds) }

    static func tab(_ id: Int = 1) -> NowPlayingSource {
        .browser(BrowserMediaKey(tabID: id, documentID: "doc-\(id)", host: "example.com", fingerprint: "f\(id)"))
    }

    func item(_ source: NowPlayingSource, _ title: String = "Song", playing: Bool = true, duration: Double = 200,
              position: Double = 10) -> NowPlaying {
        NowPlaying(source: source, title: title, artist: "Band", album: "Record", isPlaying: playing, duration: duration,
                   position: position, positionAt: clock)
    }

    /// Feeds an item for a source, one second after the last thing the rig did.
    func report(_ source: NowPlayingSource, _ title: String = "Song", playing: Bool = true, duration: Double = 200,
                announce: Bool = true) {
        advance()
        hub.update(source, item(source, title, playing: playing, duration: duration), announce: announce)
    }
}

/// Counts a change notification; the observation closure is Sendable, so the count lives in a box.
private final class Fired: @unchecked Sendable { var count = 0 }

@MainActor @Suite struct NowPlayingHubTests {
    // MARK: Commands and capabilities

    @Test func commandsOutsideTheCapabilitiesAreRefused() {
        let rig = Rig()
        rig.enableBrowser()
        rig.report(Rig.tab())
        for command in [TopBarModel.MusicCommand.next, .previous, .toggleShuffle, .cycleRepeat] { rig.hub.musicCommand(command) }
        #expect(rig.browser.isEmpty)
        #expect(rig.sent.isEmpty)
        // A source of unknown length cannot seek.
        let other = Rig()
        other.report(other.music, duration: 0)
        other.hub.seek(to: 30)
        #expect(other.seeks.isEmpty)
        // What a source can do goes through.
        other.hub.musicCommand(.next)
        #expect(other.sent.map(\.kind) == [.next])
    }

    @Test func aNilBrowserCommandDoesNothing() {
        let rig = Rig()
        rig.report(Rig.tab())
        let before = rig.model.nowPlaying
        rig.hub.musicCommand(.playPause)
        rig.hub.seek(to: 20)
        #expect(rig.sent.isEmpty && rig.seeks.isEmpty && rig.readBacks.isEmpty)
        #expect(rig.model.nowPlaying == before)
        #expect(rig.hub.pauseForDictation() == nil)
    }

    @Test func commandsGoToTheShownSource() {
        let rig = Rig()
        rig.enableBrowser()
        rig.report(rig.music)
        rig.hub.musicCommand(.next)
        #expect(rig.sent.map(\.player) == [.music])
        rig.report(Rig.tab(5))
        rig.hub.musicCommand(.playPause)
        #expect(rig.browser.map(\.key) == [BrowserMediaKey(tabID: 5, documentID: "doc-5", host: "example.com", fingerprint: "f5")])
        #expect(rig.sent.count == 1)
    }

    @Test func thePinHoldsAndTargetsTheCommands() {
        let rig = Rig()
        rig.label = "Spotify"
        rig.report(rig.music)
        // Music plays, but the pin shows only Spotify, so nothing is shown.
        #expect(rig.model.nowPlaying == nil)
        // With nothing shown the target is the pinned player.
        rig.hub.musicCommand(.playPause)
        rig.hub.musicCommand(.open)
        #expect(rig.sent.map(\.player) == [.spotify])
        #expect(rig.opened == [rig.spotify])
        #expect(rig.model.commandTarget() == rig.spotify)
        rig.report(rig.spotify, "Pinned")
        #expect(rig.model.nowPlaying?.source == rig.spotify)
        // The setting changes: the other player shows at once.
        rig.label = "Music"
        rig.hub.followChanged()
        #expect(rig.model.nowPlaying?.source == rig.music)
        rig.label = nil
        rig.hub.followChanged()
        #expect(rig.model.nowPlaying?.source == rig.spotify)
    }

    @Test func withNothingShownTheTargetIsMusicAndOpenNamesIt() {
        let rig = Rig()
        #expect(rig.model.commandTarget() == rig.music)
        rig.hub.musicCommand(.open)
        rig.hub.musicCommand(.playPause)
        #expect(rig.opened == [rig.music])
        #expect(rig.sent.map(\.player) == [.music])
        // The optimistic write needs an item; with none there is nothing to flip.
        #expect(rig.model.nowPlaying == nil)
        #expect(rig.readBacks.isEmpty)
    }

    @Test func openOnABrowserItemOpensThatSource() {
        let rig = Rig()
        rig.report(Rig.tab(2))
        rig.hub.musicCommand(.open)
        #expect(rig.opened == [Rig.tab(2)])
        #expect(rig.sent.isEmpty)
    }

    // MARK: Entries

    @Test func entriesGoWhenAFeedTurnsOff() {
        let rig = Rig()
        rig.report(rig.music)
        rig.report(rig.spotify, "Two")
        rig.report(Rig.tab(), "Three")
        #expect(rig.hub.hasPlayerSession)
        rig.hub.remove { $0.scriptedPlayer != nil }
        #expect(rig.hub.entry(rig.music) == nil && rig.hub.entry(rig.spotify) == nil)
        #expect(!rig.hub.hasPlayerSession)
        #expect(rig.model.nowPlaying?.source == Rig.tab())
        rig.hub.remove { _ in true }
        #expect(rig.model.nowPlaying == nil)
        #expect(rig.covers.last == .some(nil))
    }

    @Test func aPlayerQuitRemovesItsEntryThroughTheFeed() {
        let rig = Rig()
        rig.report(rig.music)
        rig.report(rig.spotify, "Two")
        rig.advance()
        rig.hub.update(rig.spotify, nil)
        #expect(rig.model.nowPlaying?.source == rig.music)
        rig.hub.update(rig.music, nil)
        #expect(rig.model.nowPlaying == nil)
    }

    @Test func anIdenticalSampleWritesNothing() {
        let rig = Rig()
        rig.report(rig.music)
        let fired = Fired()
        withObservationTracking { _ = rig.model.nowPlaying } onChange: { fired.count += 1 }
        // The same item again, even for another entry: the shown value is equal, so nothing is written.
        rig.hub.update(rig.music, rig.model.nowPlaying, announce: false)
        rig.hub.update(rig.spotify, rig.item(rig.spotify, playing: false), announce: false)
        #expect(fired.count == 0)
        // A different item does write.
        rig.report(rig.music, "Next song")
        #expect(fired.count == 1)
    }

    // MARK: Play and pause

    @Test func twoQuickTogglesGivePauseThenPlay() {
        let rig = Rig()
        rig.enableBrowser()
        rig.report(Rig.tab())
        rig.hub.musicCommand(.playPause)
        #expect(rig.model.nowPlaying?.isPlaying == false)
        rig.hub.musicCommand(.playPause)
        #expect(rig.model.nowPlaying?.isPlaying == true)
        #expect(rig.browser.map(\.kind) == [.pause, .play])
    }

    @Test func aPlayerKeepsItsToggleAndFlipsAtOnce() {
        let rig = Rig()
        rig.report(rig.music)
        rig.hub.musicCommand(.playPause)
        #expect(rig.model.nowPlaying?.isPlaying == false)
        rig.hub.musicCommand(.playPause)
        #expect(rig.model.nowPlaying?.isPlaying == true)
        #expect(rig.sent.map(\.kind) == [.playPause, .playPause])
    }

    @Test func theFlipKeepsTheBarWhereItWas() {
        let rig = Rig()
        rig.report(rig.music)
        rig.advance(30)
        rig.hub.musicCommand(.playPause)
        let paused = rig.model.nowPlaying
        // 10 s were in the sample and 30 s have run since: the bar holds at 40 s.
        #expect(paused?.position == 40)
        #expect(paused?.positionAt == rig.clock)
    }

    @Test func aPlayerThatCannotBeReachedIsNotFlippedAndNotReadBack() {
        let rig = Rig()
        rig.report(rig.music)
        rig.playerAccepts = false
        rig.hub.musicCommand(.playPause)
        #expect(rig.model.nowPlaying?.isPlaying == true)
        #expect(rig.readBacks.isEmpty)
    }

    @Test func aPlayPauseSentToAPlayerAsksTheFeedToReadItBack() {
        let rig = Rig()
        rig.enableBrowser()
        rig.report(rig.spotify)
        rig.hub.musicCommand(.playPause)
        #expect(rig.readBacks == [.spotify])
        rig.hub.musicCommand(.next)
        #expect(rig.readBacks == [.spotify])
        // Never for a browser source: its next poll is its read-back.
        rig.report(Rig.tab())
        rig.hub.musicCommand(.playPause)
        #expect(rig.readBacks == [.spotify])
    }

    // MARK: Seek

    @Test func aSeekIsClampedAndMovesTheBarAtOnce() {
        let rig = Rig()
        rig.enableBrowser()
        rig.report(rig.music)
        rig.hub.seek(to: 500)
        #expect(rig.seeks.map(\.seconds) == [199.5])
        #expect(rig.model.nowPlaying?.position == 199.5)
        rig.report(Rig.tab(), duration: 120)
        rig.hub.seek(to: 30)
        #expect(rig.browser.map(\.kind) == [.seek])
        #expect(rig.browser.map(\.seconds) == [30])
        #expect(rig.model.nowPlaying?.position == 30)
        // A refused player leaves the bar alone.
        let refused = Rig()
        refused.report(refused.music)
        refused.playerAccepts = false
        refused.hub.seek(to: 60)
        #expect(refused.model.nowPlaying?.position == 10)
    }

    // MARK: Dictation

    @Test func dictationPausesTheShownSourceAndResumesThatSource() {
        let rig = Rig()
        rig.enableBrowser()
        rig.report(rig.music)
        rig.report(Rig.tab(3))
        let paused = rig.hub.pauseForDictation()
        #expect(paused == Rig.tab(3))
        #expect(rig.browser.map(\.kind) == [.pause])
        #expect(rig.sent.isEmpty)
        rig.hub.resumeAfterDictation(Rig.tab(3))
        #expect(rig.browser.map(\.kind) == [.pause, .play])
        #expect(rig.sent.isEmpty, "Music is never touched by the tab's pause or resume")
    }

    @Test func dictationPausesAPlayerWithAnExplicitPause() {
        let rig = Rig()
        rig.report(rig.spotify)
        #expect(rig.hub.pauseForDictation() == rig.spotify)
        #expect(rig.sent.map(\.kind) == [.pause])
        #expect(rig.model.nowPlaying?.isPlaying == false)
        rig.hub.resumeAfterDictation(rig.spotify)
        #expect(rig.sent.map(\.kind) == [.pause, .play])
        #expect(rig.model.nowPlaying?.isPlaying == true)
    }

    @Test func dictationLeavesAPausedOrEmptyNotchAlone() {
        let rig = Rig()
        #expect(rig.hub.pauseForDictation() == nil)
        rig.report(rig.music, playing: false)
        #expect(rig.hub.pauseForDictation() == nil)
        #expect(rig.sent.isEmpty)
    }

    @Test func aResumeAfterTheSourceWasRemovedDoesNothingAndNeverReachesMusic() {
        let rig = Rig()
        rig.enableBrowser()
        rig.report(rig.music, playing: false)
        rig.report(Rig.tab(3))
        let paused = rig.hub.pauseForDictation()
        #expect(paused == Rig.tab(3))
        rig.hub.remove { $0 == Rig.tab(3) }
        rig.hub.resumeAfterDictation(Rig.tab(3))
        #expect(rig.browser.map(\.kind) == [.pause])
        #expect(rig.sent.isEmpty)
        #expect(rig.model.nowPlaying?.source == rig.music)
        #expect(rig.model.nowPlaying?.isPlaying == false)
    }

    @Test func aResumeForASourceThatAlreadyPlaysSendsNothing() {
        let rig = Rig()
        rig.report(rig.music)
        rig.hub.resumeAfterDictation(rig.music)
        #expect(rig.sent.isEmpty)
    }

    // MARK: Cue, modes, artwork, page

    @Test func theTrackCueFiresOnTheShownItemAsToday() {
        let rig = Rig()
        rig.report(rig.music, "One")
        #expect(rig.cues == [.trackChanged(title: "One", artist: "Band")])
        rig.report(rig.music, "One")
        rig.report(rig.music, "One", playing: false)
        #expect(rig.cues.count == 1, "the same track, and a pause, raise nothing")
        rig.report(rig.music, "Two", playing: false)
        #expect(rig.cues.count == 1, "a paused change of track raises nothing")
        rig.report(rig.music, "Three")
        #expect(rig.cues.last == .trackChanged(title: "Three", artist: "Band"))
        rig.report(rig.music, "Four", announce: false)
        #expect(rig.cues.count == 2, "a launch sync announces nothing")
        // An entry that is not shown raises nothing.
        rig.report(rig.spotify, "Quiet", playing: false)
        #expect(rig.cues.count == 2)
    }

    @Test func theModesBelongToTheShownSource() {
        let rig = Rig()
        rig.report(rig.music)
        #expect(rig.modeResets == 1 && rig.modeReads == [.music])
        // Spotify heard paused for the first time does not displace Music, so it neither resets nor reads.
        rig.report(rig.spotify, playing: false)
        #expect(rig.modeResets == 1 && rig.modeReads == [.music])
        // Spotify starts: it is shown now, so the modes reset and are read for it.
        rig.report(rig.spotify)
        #expect(rig.modeResets == 2 && rig.modeReads == [.music, .spotify])
        // A browser item has no scripted player: reset, never read.
        rig.report(Rig.tab())
        #expect(rig.modeResets == 3 && rig.modeReads == [.music, .spotify])
        // Nothing left to show: reset.
        rig.hub.remove { _ in true }
        #expect(rig.modeResets == 4)
    }

    @Test func artworkIsRequestedForTheShownItem() {
        let rig = Rig()
        rig.report(rig.music, "One")
        #expect(rig.covers.last??.title == "One")
        rig.report(rig.spotify, "Two", playing: false)
        #expect(rig.covers.last??.title == "One")
        rig.hub.remove { _ in true }
        #expect(rig.covers.last == .some(nil))
    }

    @Test func theMusicPageHookReachesEveryObserverOnce() {
        let rig = Rig()
        var first: [Bool] = []
        var second: [Bool] = []
        rig.hub.observeMusicPage { first.append($0) }
        rig.hub.observeMusicPage { second.append($0) }
        rig.model.musicPageVisible = true
        rig.model.musicPageVisible = true
        rig.model.musicPageVisible = false
        #expect(first == [true, false] && second == [true, false])
    }

    @Test func theFollowSettingOffersExactlyTheArbitersChoicesAndDefaultsToAnyPlayer() throws {
        let option = try #require(SettingsCatalog.option(NowPlayingHub.followSettingID))
        #expect(option.choices == NowPlayingArbiter.Follow.choices.map(\.label))
        #expect(option.defaultValue == "Any player")
        #expect(NowPlayingArbiter.Follow(label: option.defaultValue) == .any)
        #expect(option.kind == .choice)
    }

    @Test func attachingWiresTheModelsClosures() {
        let rig = Rig()
        rig.report(rig.music)
        rig.model.musicCommand(.next)
        rig.model.seek(40)
        #expect(rig.sent.map(\.kind) == [.next])
        #expect(rig.seeks.map(\.seconds) == [40])
        #expect(rig.model.pauseForDictation() == rig.music)
        rig.model.resumeAfterDictation(rig.music)
        #expect(rig.sent.map(\.kind) == [.next, .pause, .play])
        #expect(rig.model.nowPlayingHub === rig.hub)
        #expect(rig.model.nowPlayingHub?.hasPlayerSession == true)
    }
}
