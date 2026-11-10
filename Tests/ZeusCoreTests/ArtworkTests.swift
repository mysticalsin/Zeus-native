import Foundation
import Testing
@testable import ZeusCore

@Suite struct ArtworkTests {
    // Fixtures: the shapes the two public APIs answer with.
    static let oEmbed = #"""
    {"html":"<iframe></iframe>","width":456,"height":352,"version":"1.0","provider_name":"Spotify","provider_url":"https://spotify.com","type":"rich",
     "title":"Midnight City","thumbnail_url":"https://image-cdn-ak.spotifycdn.com/image/ab67616d00001e02a5f1a3b8c1f1f2d3e4c5b6a7","thumbnail_width":300,"thumbnail_height":300}
    """#
    static let iTunes = #"""
    {"resultCount":1,"results":[{"wrapperType":"collection","collectionType":"Album","artistName":"M83","collectionName":"Hurry Up, We're Dreaming",
     "artworkUrl60":"https://is1-ssl.mzstatic.com/image/thumb/Music/v4/ab/cd/ef/x.jpg/60x60bb.jpg",
     "artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Music/v4/ab/cd/ef/x.jpg/100x100bb.jpg"}]}
    """#

    @Test func spotifyTrackIDsComeFromTheNotification() {
        #expect(ArtworkSource.spotifyTrackID("spotify:track:6rqhFgbbKwnb9MLmUQDhG6") == "6rqhFgbbKwnb9MLmUQDhG6")
        #expect(ArtworkSource.spotifyTrackID("https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6?si=abc") == "6rqhFgbbKwnb9MLmUQDhG6")
        #expect(ArtworkSource.spotifyTrackID("spotify:episode:6rqhFgbbKwnb9MLmUQDhG6") == nil)
        #expect(ArtworkSource.spotifyTrackID("spotify:local:Artist::Song:200") == nil)
        #expect(ArtworkSource.spotifyTrackID(nil) == nil)
    }

    @Test func oEmbedURLCarriesTheTrackLink() throws {
        let url = try #require(ArtworkSource.spotifyOEmbedURL(trackID: "6rqhFgbbKwnb9MLmUQDhG6"))
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.host == "open.spotify.com" && parts.path == "/oembed")
        #expect(parts.queryItems?.first { $0.name == "url" }?.value == "https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6")
    }

    @Test func oEmbedParsing() throws {
        let thumb = try #require(ArtworkSource.parseOEmbed(Data(Self.oEmbed.utf8)))
        #expect(thumb.host == "image-cdn-ak.spotifycdn.com")
        // The 300 px cover becomes the 640 px one of the same image.
        #expect(ArtworkSource.spotifyFullSize(thumb).absoluteString.contains("ab67616d0000b273a5f1a3b8c1f1f2d3e4c5b6a7"))
        // Anything else stays as it is.
        let other = URL(string: "https://example.com/a.jpg")!
        #expect(ArtworkSource.spotifyFullSize(other) == other)
        #expect(ArtworkSource.parseOEmbed(Data("{}".utf8)) == nil)
        #expect(ArtworkSource.parseOEmbed(Data("not json".utf8)) == nil)
        #expect(ArtworkSource.parseOEmbed(Data(#"{"thumbnail_url":"http://insecure.example/a.jpg"}"#.utf8)) == nil)
    }

    @Test func iTunesSearchURL() throws {
        let url = try #require(ArtworkSource.iTunesSearchURL(artist: "M83", album: "Hurry Up, We're Dreaming", title: "Midnight City"))
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.host == "itunes.apple.com" && parts.path == "/search")
        let items = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["term"] == "M83 Hurry Up, We're Dreaming")
        #expect(items["entity"] == "album" && items["limit"] == "1")
        // No album: search the song.
        let song = try #require(ArtworkSource.iTunesSearchURL(artist: "M83", album: "", title: "Midnight City"))
        #expect(URLComponents(url: song, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "entity" }?.value == "song")
        #expect(ArtworkSource.iTunesSearchURL(artist: " ", album: "", title: "") == nil)
    }

    @Test func iTunesParsingUpscalesTo600() throws {
        let url = try #require(ArtworkSource.parseITunes(Data(Self.iTunes.utf8)))
        #expect(url.absoluteString.hasSuffix("/600x600bb.jpg"))
        #expect(ArtworkSource.parseITunes(Data(Self.iTunes.utf8), size: 1000)?.absoluteString.hasSuffix("/1000x1000bb.jpg") == true)
        #expect(ArtworkSource.parseITunes(Data(#"{"resultCount":0,"results":[]}"#.utf8)) == nil)
        #expect(ArtworkSource.parseITunes(Data("oops".utf8)) == nil)
        let plain = URL(string: "https://example.com/cover.jpg")!
        #expect(ArtworkSource.upscale(plain, to: 600) == plain)
    }

    @Test func cacheKeys() {
        func playing(_ player: NowPlaying.Player, artist: String = "M83", album: String = "Hurry Up", title: String = "Midnight City", id: String? = nil) -> NowPlaying {
            NowPlaying(player: player, title: title, artist: artist, album: album, isPlaying: true, duration: 1, position: 0, trackID: id)
        }
        // Spotify: by track.
        #expect(ArtworkSource.cacheKey(for: playing(.spotify, id: "spotify:track:abc123")) == "spotify-abc123")
        // Music: one key per album, whatever the track, case and accents.
        let a = ArtworkSource.cacheKey(for: playing(.music))
        #expect(a == ArtworkSource.cacheKey(for: playing(.music, title: "Another Song")))
        #expect(a == ArtworkSource.cacheKey(for: playing(.music, artist: "m83 ", album: "HURRY UP")))
        #expect(a != ArtworkSource.cacheKey(for: playing(.music, album: "Junk")))
        #expect(a.hasPrefix("music-"))
        // Safe as a file name.
        #expect(a.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
        // No album: the title stands in.
        #expect(ArtworkSource.cacheKey(for: playing(.music, album: "")) != a)
    }

    @Test func cacheEvictsLeastRecentlyUsedFirst() {
        let now = Date()
        let entries = [
            ArtworkCachePolicy.Entry(name: "old", bytes: 20_000_000, lastUsed: now.addingTimeInterval(-300)),
            ArtworkCachePolicy.Entry(name: "mid", bytes: 20_000_000, lastUsed: now.addingTimeInterval(-200)),
            ArtworkCachePolicy.Entry(name: "new", bytes: 20_000_000, lastUsed: now.addingTimeInterval(-100)),
        ]
        #expect(ArtworkCachePolicy.evictions(entries) == ["old"])
        #expect(ArtworkCachePolicy.evictions(entries, limit: 100_000_000).isEmpty)
        #expect(ArtworkCachePolicy.evictions(entries, limit: 25_000_000) == ["old", "mid"])
        #expect(ArtworkCachePolicy.limitBytes == 50_000_000)
    }

    @Test func averageColourAndGlow() throws {
        // Two red pixels and two transparent ones: red only.
        let red = try #require(ArtworkColor.average(rgba: [255, 0, 0, 255, 255, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0]))
        #expect(red.red > 0.99 && red.green < 0.01 && red.blue < 0.01)
        #expect(ArtworkColor.average(rgba: []) == nil)
        #expect(ArtworkColor.average(rgba: [10, 10, 10, 0]) == nil)
        // A dark cover still glows: brighter than it was, hue kept.
        let dark = ArtworkColor.RGB(red: 0.2, green: 0.05, blue: 0.05)
        let lit = ArtworkColor.glow(dark)
        #expect(lit.red > dark.red * 2 && lit.red > lit.green && lit.red > lit.blue)
        #expect(lit.red <= 1 && lit.green >= 0)
    }

    @Test func notificationCarriesTheSpotifyTrackID() {
        let playing = NowPlaying.parse(["Name": "S", "Player State": "Playing", "Duration": 90_000, "Track ID": "spotify:track:6rqhFgbbKwnb9MLmUQDhG6"], player: .spotify)
        #expect(playing?.trackID == "spotify:track:6rqhFgbbKwnb9MLmUQDhG6")
        let music = NowPlaying.parse(["Name": "S", "Player State": "Playing", "Total Time": 90_000, "Track ID": "123"], player: .music)
        #expect(music?.trackID == nil)
    }
}

@Suite struct MusicSeekTests {
    @Test func dragMapsToSeconds() {
        #expect(MusicSeek.fraction(x: 50, width: 200) == 0.25)
        #expect(MusicSeek.fraction(x: -10, width: 200) == 0)
        #expect(MusicSeek.fraction(x: 999, width: 200) == 1)
        #expect(MusicSeek.fraction(x: 10, width: 0) == 0)
        #expect(MusicSeek.seconds(fraction: 0.5, duration: 240) == 120)
        #expect(MusicSeek.seconds(fraction: 1.5, duration: 240) == 240)
        #expect(MusicSeek.seconds(fraction: -1, duration: 240) == 0)
        #expect(MusicSeek.seconds(fraction: 0.5, duration: 0) == nil)
        #expect(MusicSeek.seconds(fraction: .nan, duration: 100) == nil)
        #expect(MusicSeek.fraction(elapsed: 60, duration: 240) == 0.25)
        #expect(MusicSeek.fraction(elapsed: 60, duration: 0) == 0)
    }

    @Test func seekToTheEndStopsJustShort() {
        #expect(MusicSeek.clampedTarget(240, duration: 240) == 239.5)
        #expect(MusicSeek.clampedTarget(-5, duration: 240) == 0)
        #expect(MusicSeek.clampedTarget(100, duration: 240) == 100)
    }

    @Test func scriptsTargetEachPlayer() {
        #expect(MusicSeek.script(player: .spotify, seconds: 83.456) == "tell application id \"com.spotify.client\" to set player position to 83.46")
        #expect(MusicSeek.script(player: .music, seconds: 12) == "tell application id \"com.apple.Music\" to set player position to 12.00")
        #expect(MusicSeek.script(player: .music, seconds: -3).hasSuffix("0.00"))
    }
}
