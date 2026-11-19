import Foundation
import Testing
@testable import ZeusCore

@Suite struct NowPlayingSourceTests {
    static let key = BrowserMediaKey(tabID: 7, documentID: "doc-1", host: "example.com", fingerprint: "ab12cd")
    /// Every kind of source Zeus knows. A new kind is one more row here.
    static let samples: [NowPlayingSource] = [.player(.music), .player(.spotify), .browser(key)]

    private func item(_ source: NowPlayingSource, artist: String = "Band", duration: Double = 200,
                      isPlaying: Bool = true) -> NowPlaying {
        NowPlaying(source: source, title: "Song", artist: artist, album: "Record", isPlaying: isPlaying,
                   duration: duration, position: 10)
    }

    @Test func namesAndBundleIDs() {
        #expect(NowPlayingSource.player(.music).kindName == "Music")
        #expect(NowPlayingSource.player(.spotify).kindName == "Spotify")
        #expect(NowPlayingSource.browser(Self.key).kindName == "Chrome")
        #expect(NowPlayingSource.player(.music).appBundleID == "com.apple.Music")
        #expect(NowPlayingSource.player(.spotify).appBundleID == "com.spotify.client")
        #expect(NowPlayingSource.browser(Self.key).appBundleID == "com.google.Chrome")
        for source in Self.samples { #expect(!source.kindName.isEmpty && !source.appBundleID.isEmpty) }
    }

    @Test func playersAreCaseIterableAndKeepTheirOwnFacts() {
        #expect(NowPlaying.Player.allCases == [.music, .spotify])
        #expect(NowPlayingSource.player(.music).scriptedPlayer == .music)
        #expect(NowPlayingSource.player(.spotify).scriptedPlayer == .spotify)
        #expect(NowPlayingSource.browser(Self.key).scriptedPlayer == nil)
    }

    @Test func baseSetsKeepWhatPlayersDoToday() {
        let everything: SourceCapabilities = [.playPause, .next, .previous, .seek, .shuffle, .repeatMode, .lyrics]
        #expect(NowPlayingSource.player(.music).baseCapabilities == everything)
        // Spotify's shuffle and repeat work today (the modes are scripted and read back), so they stay.
        #expect(NowPlayingSource.player(.spotify).baseCapabilities == everything)
        let browser = NowPlayingSource.browser(Self.key).baseCapabilities
        #expect(browser.contains(.playPause))
        for missing in [SourceCapabilities.next, .previous, .shuffle, .repeatMode] { #expect(!browser.contains(missing)) }
    }

    @Test func artworkAndStorageFollowTheKind() {
        #expect(NowPlayingSource.player(.spotify).artworkStrategy == .spotifyOEmbed)
        #expect(NowPlayingSource.player(.music).artworkStrategy == .catalogSearch)
        #expect(NowPlayingSource.browser(Self.key).artworkStrategy == .pageImage)
        #expect(NowPlayingSource.player(.music).persistsDerivedData)
        #expect(NowPlayingSource.player(.spotify).persistsDerivedData)
        #expect(!NowPlayingSource.browser(Self.key).persistsDerivedData)
    }

    @Test func seekNeedsADurationForEverySource() {
        for source in Self.samples {
            #expect(item(source, duration: 200).capabilities.contains(.seek))
            #expect(!item(source, duration: 0).capabilities.contains(.seek))
        }
    }

    @Test func lyricsNeedAnArtistAndABrowserItemAlsoNeedsADuration() {
        for player in NowPlaying.Player.allCases {
            #expect(item(.player(player)).capabilities.contains(.lyrics))
            #expect(!item(.player(player), artist: "").capabilities.contains(.lyrics))
            #expect(!item(.player(player), artist: "  ").capabilities.contains(.lyrics))
        }
        let browser = NowPlayingSource.browser(Self.key)
        #expect(item(browser).capabilities.contains(.lyrics))
        #expect(!item(browser, artist: "").capabilities.contains(.lyrics))
        #expect(!item(browser, duration: 0).capabilities.contains(.lyrics))
    }

    @Test func aPlayerItemOfUnknownLengthKeepsItsLyricsAsToday() {
        // Same rule as before the source model: lyrics hold exactly when the query is askable.
        let music = item(.player(.music), duration: 0)
        #expect(music.capabilities.contains(.lyrics) == LRCLIBQuery(music).isAskable)
        #expect(music.capabilities.contains(.lyrics))
        #expect(!music.capabilities.contains(.seek))
        for player in NowPlaying.Player.allCases {
            for artist in ["Band", ""] {
                let playing = item(.player(player), artist: artist, duration: 0)
                #expect(playing.capabilities.contains(.lyrics) == LRCLIBQuery(playing).isAskable)
            }
        }
    }

    @Test func itemCapabilitiesNeverExceedTheBaseSet() {
        for source in Self.samples {
            for duration in [0.0, 200] {
                for artist in ["", "Band"] {
                    let capabilities = item(source, artist: artist, duration: duration).capabilities
                    #expect(source.baseCapabilities.isSuperset(of: capabilities))
                }
            }
        }
    }

    @Test func allowsMirrorsEveryCommandKind() {
        let music = item(.player(.music)).capabilities
        for kind in MusicCommandKind.allCases { #expect(music.allows(kind)) }
        let browser = item(.browser(Self.key)).capabilities
        let allowed: Set<MusicCommandKind> = [.play, .pause, .playPause, .seek, .open]
        for kind in MusicCommandKind.allCases { #expect(browser.allows(kind) == allowed.contains(kind)) }
        // Without a duration the scrubber has nothing to seek.
        #expect(!item(.player(.music), duration: 0).capabilities.allows(.seek))
        // Open is never a capability: every source can be opened, even with none.
        #expect(SourceCapabilities().allows(.open))
        for kind in MusicCommandKind.allCases where kind != .open { #expect(!SourceCapabilities().allows(kind)) }
    }

    @Test func explicitPlayAndPauseShareThePlayPauseCapability() {
        #expect(SourceCapabilities.playPause.allows(.play))
        #expect(SourceCapabilities.playPause.allows(.pause))
        #expect(SourceCapabilities.playPause.allows(.playPause))
        #expect(!SourceCapabilities.next.allows(.play))
    }

    @Test func extrapolationUsesTheRate() {
        let start = Date(timeIntervalSince1970: 500)
        func playing(rate: Double, isPlaying: Bool = true) -> NowPlaying {
            NowPlaying(source: .player(.music), title: "S", artist: "A", album: "", isPlaying: isPlaying,
                       duration: 100, position: 10, positionAt: start, rate: rate)
        }
        let later = start.addingTimeInterval(10)
        #expect(playing(rate: 1).elapsed(at: later) == 20)
        #expect(playing(rate: 2).elapsed(at: later) == 30)
        #expect(playing(rate: 0).elapsed(at: later) == 10)
        #expect(playing(rate: 2, isPlaying: false).elapsed(at: later) == 10)
        #expect(playing(rate: 2).elapsed(at: start.addingTimeInterval(1000)) == 100)
        #expect(playing(rate: -3).elapsed(at: later) == 10)
    }

    @Test func playerInitializerStaysAndDefaultsTheNewFields() {
        let playing = NowPlaying(player: .spotify, title: "S", artist: "A", album: "B", isPlaying: true, duration: 90, position: 3)
        #expect(playing.source == .player(.spotify))
        #expect(playing.rate == 1)
        #expect(playing.artworkURL == nil)
    }

    @Test func aChangeOfSourceReadsTheModesAgain() {
        let music = item(.player(.music))
        let spotify = item(.player(.spotify))
        let known = MusicModes(shuffle: false, repeatMode: .off)
        #expect(MusicModeRules.shouldRead(previous: music, current: spotify, modes: known))
        #expect(MusicModeRules.shouldRead(previous: item(.browser(Self.key)), current: music, modes: known))
        #expect(!MusicModeRules.shouldRead(previous: music, current: music, modes: known))
    }
}
