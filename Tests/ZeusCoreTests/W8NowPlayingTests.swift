import Foundation
import Testing
@testable import ZeusCore

@Suite struct W8NowPlayingTests {
    private let sep = NowPlaying.probeSeparator

    @Test func spotifyNotificationKeys() {
        let info: [AnyHashable: Any] = [
            "Player State": "Playing", "Name": "Song", "Artist": "Band", "Album": "Record",
            "Duration": 215_000, "Playback Position": 12.5, "Track ID": "spotify:track:abc",
        ]
        let playing = NowPlaying.parse(info, player: .spotify)
        #expect(playing?.title == "Song")
        #expect(playing?.artist == "Band")
        #expect(playing?.album == "Record")
        #expect(playing?.isPlaying == true)
        #expect(playing?.duration == 215)
        #expect(playing?.position == 12.5)
        #expect(playing?.trackID == "spotify:track:abc")
    }

    @Test func spotifyPausedIsNotPlaying() {
        let info: [AnyHashable: Any] = ["Player State": "Paused", "Name": "Song", "Duration": 1000]
        let playing = NowPlaying.parse(info, player: .spotify)
        #expect(playing?.isPlaying == false)
    }

    @Test func musicNotificationKeys() {
        let info: [AnyHashable: Any] = [
            "Player State": "Playing", "Name": "Tune", "Artist": "Duo", "Album": "LP", "Total Time": 180_000,
        ]
        let playing = NowPlaying.parse(info, player: .music)
        #expect(playing?.duration == 180)
        #expect(playing?.position == 0)
        #expect(playing?.trackID == nil)
        #expect(playing?.isPlaying == true)
    }

    @Test func stoppedAndNamelessAreNil() {
        #expect(NowPlaying.parse(["Player State": "Stopped", "Name": "Song"], player: .music) == nil)
        #expect(NowPlaying.parse(["Player State": "Stopped"], player: .spotify) == nil)
        #expect(NowPlaying.parse(["Player State": "Playing", "Name": ""], player: .spotify) == nil)
    }

    @Test func stateIsCaseInsensitive() {
        #expect(NowPlaying.parse(["Player State": "playing", "Name": "A"], player: .music)?.isPlaying == true)
        #expect(NowPlaying.parse(["Player State": "stopped", "Name": "A"], player: .music) == nil)
    }

    @Test func bundleIDRoundTrip() {
        #expect(NowPlaying.Player(bundleID: "com.apple.Music") == .music)
        #expect(NowPlaying.Player(bundleID: "com.spotify.client") == .spotify)
        #expect(NowPlaying.Player(bundleID: "com.example.other") == nil)
    }

    @Test func probeScriptTargetsThePlayerOnly() {
        let script = NowPlaying.probeScript(player: .spotify)
        #expect(script.contains("tell application id \"com.spotify.client\""))
        #expect(script.contains("return \"stopped\""))
        // The running check precedes the tell, so a quit player is never relaunched.
        let guardLine = script.range(of: "is not running then return")
        let tell = script.range(of: "tell application id")
        #expect(guardLine != nil && tell != nil && guardLine!.lowerBound < tell!.lowerBound)
    }

    @Test func probeParsesMusicSeconds() {
        let out = ["playing", "Tune", "Duo", "LP", "180.5", "42.25"].joined(separator: sep)
        let playing = NowPlaying.parseProbe(out + "\n", player: .music)
        #expect(playing?.title == "Tune")
        #expect(playing?.duration == 180.5)
        #expect(playing?.position == 42.25)
        #expect(playing?.isPlaying == true)
    }

    @Test func probeParsesSpotifyMillisecondsAndLocaleComma() {
        let out = ["paused", "Song", "Band", "Record", "215000", "12,5"].joined(separator: sep)
        let playing = NowPlaying.parseProbe(out, player: .spotify)
        #expect(playing?.duration == 215)
        #expect(playing?.position == 12.5)
        #expect(playing?.isPlaying == false)
    }

    @Test func probeKeepsEmptyArtistAndAlbum() {
        let out = ["playing", "Podcast", "", "", "60", "1"].joined(separator: sep)
        let playing = NowPlaying.parseProbe(out, player: .music)
        #expect(playing?.title == "Podcast")
        #expect(playing?.artist == "")
        #expect(playing?.album == "")
    }

    @Test func probeRejectsStoppedGarbageAndNil() {
        #expect(NowPlaying.parseProbe("stopped", player: .music) == nil)
        #expect(NowPlaying.parseProbe("", player: .music) == nil)
        #expect(NowPlaying.parseProbe(nil, player: .spotify) == nil)
        #expect(NowPlaying.parseProbe(["stopped", "x", "", "", "1", "1"].joined(separator: sep), player: .music) == nil)
        #expect(NowPlaying.parseProbe(["playing", "", "", "", "1", "1"].joined(separator: sep), player: .music) == nil)
    }
}
