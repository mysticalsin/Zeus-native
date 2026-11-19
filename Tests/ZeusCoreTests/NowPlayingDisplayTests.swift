import Foundation
import Testing
@testable import ZeusCore

@Suite struct NowPlayingDisplayTests {
    static let music = NowPlayingSource.player(.music)
    static let spotify = NowPlayingSource.player(.spotify)

    static func tab(host: String = "example.com", tabID: Int = 7, fingerprint: String = "ab12cd") -> NowPlayingSource {
        .browser(BrowserMediaKey(tabID: tabID, documentID: "doc-\(tabID)", host: host, fingerprint: fingerprint))
    }

    private func item(_ source: NowPlayingSource, title: String = "Song", artist: String = "Band", duration: Double = 200,
                      isPlaying: Bool = true) -> NowPlaying {
        NowPlaying(source: source, title: title, artist: artist, album: "Record", isPlaying: isPlaying,
                   duration: duration, position: 10)
    }

    // MARK: Source line

    @Test func theSourceLineNamesThePlayerOrTheBrowserAndItsHost() {
        #expect(NowPlayingDisplay.sourceLine(Self.music) == "Music")
        #expect(NowPlayingDisplay.sourceLine(Self.spotify) == "Spotify")
        #expect(NowPlayingDisplay.sourceLine(Self.tab()) == "Chrome \u{00B7} example.com")
    }

    @Test func anEmptyHostShowsTheKindNameAlone() {
        #expect(NowPlayingDisplay.sourceLine(Self.tab(host: "")) == "Chrome")
        #expect(NowPlayingDisplay.sourceLine(Self.tab(host: "  \n")) == "Chrome")
        #expect(NowPlayingDisplay.sourceLine(Self.tab(host: " example.com ")) == "Chrome \u{00B7} example.com")
    }

    @Test func noSourceLineHoldsADash() {
        for source in [Self.music, Self.spotify, Self.tab(), Self.tab(host: "")] {
            let line = NowPlayingDisplay.sourceLine(source)
            #expect(!line.contains("\u{2014}") && !line.contains("\u{2013}"))
        }
    }

    // MARK: Glyph and open label

    @Test func theGlyphFollowsTheSource() {
        #expect(NowPlayingDisplay.glyph(for: Self.music) == "music.note")
        #expect(NowPlayingDisplay.glyph(for: Self.spotify) == "dot.radiowaves.left.and.right")
        #expect(NowPlayingDisplay.glyph(for: Self.tab()) == "globe")
    }

    @Test func theOpenLabelNamesTheApp() {
        #expect(NowPlayingDisplay.openLabel(for: Self.music) == "Open Music")
        #expect(NowPlayingDisplay.openLabel(for: Self.spotify) == "Open Spotify")
        #expect(NowPlayingDisplay.openLabel(for: Self.tab()) == "Open Chrome")
        #expect(NowPlayingDisplay.openLabel(for: Self.tab(host: "")) == "Open Chrome")
    }

    // MARK: Visible controls

    private static let everything: NowPlayingDisplay.Controls =
        [.previous, .playPause, .next, .shuffle, .repeatMode, .scrub, .lyrics, .open]

    @Test func musicAndSpotifyDrawEveryControl() {
        #expect(NowPlayingDisplay.visibleControls(for: item(Self.music)) == Self.everything)
        #expect(NowPlayingDisplay.visibleControls(for: item(Self.spotify)) == Self.everything)
    }

    @Test func aBrowserItemDrawsNoPreviousNextShuffleOrRepeat() {
        let controls = NowPlayingDisplay.visibleControls(for: item(Self.tab()))
        #expect(controls == [.playPause, .scrub, .lyrics, .open])
        for hidden in [NowPlayingDisplay.Controls.previous, .next, .shuffle, .repeatMode] { #expect(!controls.contains(hidden)) }
    }

    @Test func withoutADurationThereIsNoScrub() {
        // A browser item also needs a length for lyrics, so it keeps only play and open.
        #expect(NowPlayingDisplay.visibleControls(for: item(Self.tab(), duration: 0)) == [.playPause, .open])
        // A player keeps its lyrics: its lookup does not need a length.
        #expect(NowPlayingDisplay.visibleControls(for: item(Self.music, duration: 0)) == Self.everything.subtracting(.scrub))
    }

    @Test func withoutAnArtistThereIsNoLyricsButTheRestStays() {
        let controls = NowPlayingDisplay.visibleControls(for: item(Self.spotify, artist: ""))
        #expect(!controls.contains(.lyrics))
        #expect(controls == Self.everything.subtracting(.lyrics))
    }

    @Test func nothingPlayingShowsTodaysControls() {
        let controls = NowPlayingDisplay.visibleControls(for: nil)
        #expect(controls == [.previous, .playPause, .next, .shuffle, .repeatMode, .lyrics, .open])
        #expect(!controls.contains(.scrub), "no item, so there is no progress line to scrub")
    }

    @Test func openAndPlayPauseAreNeverDropped() {
        for source in [Self.music, Self.spotify, Self.tab()] {
            for duration in [0.0, 200] {
                let controls = NowPlayingDisplay.visibleControls(for: item(source, artist: "", duration: duration))
                #expect(controls.contains(.open) && controls.contains(.playPause))
            }
        }
    }

    @Test func everyDrawnControlIsOneTheItemCanHonour() {
        let pairs: [(NowPlayingDisplay.Controls, MusicCommandKind)] = [
            (.previous, .previous), (.playPause, .playPause), (.next, .next), (.shuffle, .toggleShuffle),
            (.repeatMode, .cycleRepeat), (.scrub, .seek), (.open, .open),
        ]
        for source in [Self.music, Self.spotify, Self.tab()] {
            for duration in [0.0, 200] {
                let playing = item(source, duration: duration)
                let controls = NowPlayingDisplay.visibleControls(for: playing)
                for (control, command) in pairs where controls.contains(control) {
                    #expect(playing.capabilities.allows(command))
                }
                for (control, command) in pairs where playing.capabilities.allows(command) {
                    #expect(controls.contains(control), "a control the item can honour stays drawn")
                }
            }
        }
    }

    // MARK: Accessibility label

    @Test func theLabelSpeaksTheSourceAndTheTitle() {
        #expect(NowPlayingDisplay.accessibilityLabel(for: item(Self.spotify, title: "Midnight City")) == "Playing in Spotify: Midnight City")
        #expect(NowPlayingDisplay.accessibilityLabel(for: item(Self.music, title: "Midnight City")) == "Playing in Music: Midnight City")
    }

    @Test func thePausedLabelSaysPausedAndABrowserNamesItsHost() {
        #expect(NowPlayingDisplay.accessibilityLabel(for: item(Self.music, isPlaying: false)) == "Paused in Music: Song")
        #expect(NowPlayingDisplay.accessibilityLabel(for: item(Self.tab())) == "Playing in Chrome, example.com: Song")
        #expect(NowPlayingDisplay.accessibilityLabel(for: item(Self.tab(host: ""))) == "Playing in Chrome: Song")
    }

    // MARK: Cue text

    @Test func withinOneSourceTheCueKeepsTitleAndArtist() {
        #expect(NowPlayingDisplay.cueText(title: "Song", artist: "Band", source: Self.spotify, sourceChanged: false) == "Song \u{00B7} Band")
        #expect(NowPlayingDisplay.cueText(title: "Song", artist: "", source: Self.spotify, sourceChanged: false) == "Song")
    }

    @Test func aChangeOfSourceNamesTheSourceFirst() {
        #expect(NowPlayingDisplay.cueText(title: "Song", artist: "Band", source: Self.spotify, sourceChanged: true) == "Spotify \u{00B7} Song")
        #expect(NowPlayingDisplay.cueText(title: "Song", artist: "Band", source: Self.music, sourceChanged: true) == "Music \u{00B7} Song")
        #expect(NowPlayingDisplay.cueText(title: "Song", artist: "Band", source: Self.tab(), sourceChanged: true) == "Chrome \u{00B7} Song",
                "the host stays out of the cue, the wing is narrow")
    }

    @Test func aCueWithNoSourceReadsAsItDoesToday() {
        #expect(NowPlayingDisplay.cueText(title: "Song", artist: "Band", source: nil, sourceChanged: true) == "Song \u{00B7} Band")
        #expect(NowPlayingDisplay.cueText(title: "Song", artist: "", source: nil, sourceChanged: false) == "Song")
    }

    @Test func theCueGlyphFollowsTheSourceAndFallsBackToTheNote() {
        #expect(NowPlayingDisplay.cueGlyph(for: Self.tab()) == "globe")
        #expect(NowPlayingDisplay.cueGlyph(for: Self.spotify) == "dot.radiowaves.left.and.right")
        #expect(NowPlayingDisplay.cueGlyph(for: nil) == "music.note")
    }

    // MARK: When the shown source changed

    @Test func theSourceChangedWhenItWasNothingOrAnotherKind() {
        #expect(NowPlayingDisplay.sourceChanged(from: nil, to: Self.music))
        #expect(NowPlayingDisplay.sourceChanged(from: Self.music, to: Self.spotify))
        #expect(NowPlayingDisplay.sourceChanged(from: Self.spotify, to: Self.tab()))
        #expect(NowPlayingDisplay.sourceChanged(from: Self.tab(), to: Self.music))
    }

    @Test func theSourceIsTheSameAcrossTracksAndTabsOnOneHost() {
        #expect(!NowPlayingDisplay.sourceChanged(from: Self.music, to: Self.music))
        #expect(!NowPlayingDisplay.sourceChanged(from: Self.tab(fingerprint: "a"), to: Self.tab(fingerprint: "b")))
        #expect(!NowPlayingDisplay.sourceChanged(from: Self.tab(tabID: 1), to: Self.tab(tabID: 2)))
        #expect(NowPlayingDisplay.sourceChanged(from: Self.tab(host: "a.example"), to: Self.tab(host: "b.example")))
    }

    // MARK: The cue carries the source

    @Test func theTrackCueCarriesItsSourceAndWhetherItChanged() {
        let cue = NotchCue.trackChanged(title: "Song", artist: "Band", source: Self.spotify, sourceChanged: true)
        #expect(cue == .trackChanged(title: "Song", artist: "Band", source: Self.spotify, sourceChanged: true))
        #expect(cue != .trackChanged(title: "Song", artist: "Band", source: Self.music, sourceChanged: true))
        #expect(cue != .trackChanged(title: "Song", artist: "Band", source: Self.spotify, sourceChanged: false))
        #expect(cue.duration == 3.0)
    }
}
