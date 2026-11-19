import Foundation
import Testing
@testable import ZeusCore

/// Lyric matching and polite failure (plan M2): title clean-up, candidate ranking, the three request URLs,
/// HTTP status mapping and the back-off sequence. No network anywhere.
@Suite struct LyricsMatchingTests {
    // MARK: Title clean-up

    @Test func versionSuffixesAreStripped() {
        let table: [(String, String)] = [
            ("Money for Nothing - Remastered 2011", "Money for Nothing"),
            ("Heroes - 2017 Remaster", "Heroes"),
            ("Song (Remastered 2009)", "Song"),
            ("Song [2011 Remaster]", "Song"),
            ("Song - Remastered", "Song"),
            ("Song - Remastered Version", "Song"),
            ("Song - Digitally Remastered 2009", "Song"),
            ("Song (Deluxe Edition)", "Song"),
            ("Song (Deluxe)", "Song"),
            ("Song - Deluxe Version", "Song"),
            ("Song (Expanded Edition)", "Song"),
            ("Song - Single Version", "Song"),
            ("Song (Album Version)", "Song"),
            ("Song - Radio Edit", "Song"),
            ("Song (Radio Edit)", "Song"),
            ("Song - Mono Version", "Song"),
            ("Song (Stereo)", "Song"),
            ("Song (Bonus Track)", "Song"),
            ("Song - Bonus Track Version", "Song"),
            ("Song (Explicit)", "Song"),
            ("Song [Clean]", "Song"),
            ("Song (feat. Someone)", "Song"),
            ("Song (ft. Someone Else)", "Song"),
            ("Song [featuring Someone]", "Song"),
            ("Song (Feat Someone)", "Song"),
            ("Song (feat. A) - Remastered 2011", "Song"),
            ("Song - Remastered 2011 (Deluxe Edition)", "Song"),
            ("Song (Live) (Remastered 2011)", "Song (Live)"),
            ("SONG - REMASTERED 2011", "SONG"),
            ("Song \u{2013} Remastered 2011", "Song"),
            ("Song \u{2014} Single Version", "Song"),
            ("  Song - Remastered 2011  ", "Song"),
        ]
        for (input, expected) in table {
            #expect(LyricsTitle.stripped(input) == expected, "\(input)")
        }
    }

    @Test func titlesThatMustNotChange() {
        let unchanged = [
            "Live and Let Die",
            "Remaster of the Universe",
            "Song (Live at Wembley)",
            "Song - Live",
            "Song (Live)",
            "Song - Live at Wembley 1985",
            "Hello",
            "Remastered",
            "(Remastered 2011)",
            "Single Version",
            "Deluxe",
            "Mono",
            "Feat. Me",
            "Radio Edit Radio",
            "Song (Remix)",
            "Song - Radio Mix",
            "",
        ]
        for title in unchanged {
            #expect(LyricsTitle.stripped(title) == title, "\(title)")
        }
    }

    @Test func primaryArtistIsTheFirstCredited() {
        let table: [(String, String)] = [
            ("Queen", "Queen"),
            ("Queen & David Bowie", "Queen"),
            ("Artist A, Artist B", "Artist A"),
            ("Artist A feat. Artist B", "Artist A"),
            ("Artist A Feat Artist B", "Artist A"),
            ("Artist A ft. Artist B", "Artist A"),
            ("Artist A featuring Artist B", "Artist A"),
            ("Artist A; Artist B", "Artist A"),
            ("Artist A / Artist B", "Artist A"),
            ("  Artist A , Artist B ", "Artist A"),
            ("AC/DC", "AC/DC"),
            ("Prefix", "Prefix"),
            ("Leftfield", "Leftfield"),
            ("", ""),
            // Known trade-off: this rule only feeds the search step, which the length check backs up.
            // The /api/get step uses withoutFeaturedArtists, so these names reach it whole.
            ("Simon & Garfunkel", "Simon"),
            ("Earth, Wind & Fire", "Earth"),
            ("Tyler, The Creator", "Tyler"),
        ]
        for (input, expected) in table {
            #expect(LyricsTitle.primaryArtist(input) == expected, "\(input)")
        }
    }

    @Test func onlyAFeaturedCreditIsCutFromTheArtist() {
        let table: [(String, String)] = [
            ("Queen", "Queen"),
            ("Artist A feat. Artist B", "Artist A"),
            ("Artist A Feat Artist B", "Artist A"),
            ("Artist A ft. Artist B", "Artist A"),
            ("Artist A FT Artist B", "Artist A"),
            ("Artist A featuring Artist B", "Artist A"),
            ("Queen & David Bowie", "Queen & David Bowie"),
            ("Earth, Wind & Fire", "Earth, Wind & Fire"),
            ("Simon & Garfunkel", "Simon & Garfunkel"),
            ("Artist A; Artist B", "Artist A; Artist B"),
            ("Earth, Wind & Fire feat. Someone", "Earth, Wind & Fire"),
            ("Leftfield", "Leftfield"),
            ("Prefix", "Prefix"),
            (" feat. Someone", " feat. Someone"),
            ("", ""),
        ]
        for (input, expected) in table {
            #expect(LyricsTitle.withoutFeaturedArtists(input) == expected, "\(input)")
        }
    }

    // MARK: Candidates and ranking

    private func candidate(_ id: Int, _ title: String = "Song", artist: String = "Artist", duration: Double = 200,
                           synced: String? = nil, plain: String? = nil, instrumental: Bool = false) -> LyricsCandidate {
        LyricsCandidate(id: id, title: title, artist: artist, duration: duration, instrumental: instrumental,
                        syncedText: synced, plainText: plain)
    }

    private static let lrc = "[00:01.00] one\n[00:02.00] two"

    @Test func searchResponseParses() throws {
        let body = """
        [{"id":11,"name":"Song","trackName":"Song","artistName":"Artist","albumName":"Album","duration":201.7,
          "instrumental":false,"plainLyrics":"one\\ntwo","syncedLyrics":"[00:01.00] one\\n[00:02.00] two"},
         {"id":12,"trackName":"Song (Live)","artistName":"Artist","duration":240,"instrumental":false,"plainLyrics":"la la","syncedLyrics":null},
         {"id":13,"trackName":"Song Instrumental","artistName":"Artist","duration":190,"instrumental":true,"plainLyrics":null,"syncedLyrics":null},
         "junk", 7]
        """
        let list = LRCLIBResponse.parseSearch(Data(body.utf8))
        #expect(list.map(\.id) == [11, 12, 13])
        let first = try #require(list.first)
        #expect(first.title == "Song" && first.artist == "Artist" && first.duration == 201.7)
        #expect(first.syncedText == "[00:01.00] one\n[00:02.00] two" && first.plainText == "one\ntwo")
        #expect(list[1].syncedText == nil && list[1].plainText == "la la")
        #expect(list[2].instrumental)
    }

    @Test func searchResponseToleratesGarbage() {
        #expect(LRCLIBResponse.parseSearch(Data()).isEmpty)
        #expect(LRCLIBResponse.parseSearch(Data("not json".utf8)).isEmpty)
        #expect(LRCLIBResponse.parseSearch(Data(#"{"code":404,"name":"NotFound"}"#.utf8)).isEmpty)
        #expect(LRCLIBResponse.parseSearch(Data("[]".utf8)).isEmpty)
        let sparse = LRCLIBResponse.parseSearch(Data(#"[{"id":1,"syncedLyrics":"","plainLyrics":"  "}]"#.utf8))
        #expect(sparse.count == 1)
        #expect(sparse[0].syncedText == nil && sparse[0].plainText == nil && sparse[0].title == "" && sparse[0].duration == 0)
    }

    @Test func candidateResultFollowsTheLyricsItHolds() {
        #expect(candidate(1, synced: Self.lrc, plain: "x").result == .synced(LRC.parse(Self.lrc)))
        #expect(candidate(2, synced: "[ti:only a tag]", plain: "words").result == .plain("words"))
        #expect(candidate(3, plain: "words").result == .plain("words"))
        #expect(candidate(4, instrumental: true).result == .instrumental)
        #expect(candidate(5, synced: Self.lrc, instrumental: true).result == .instrumental)
        #expect(candidate(6).result == LyricsResult.none)
    }

    @Test func syncedBeatsPlainInsideTheWindow() {
        let plainNearer = candidate(1, duration: 200, plain: "words")
        let syncedFarther = candidate(2, duration: 201.5, synced: Self.lrc)
        #expect(LyricsMatch.best([plainNearer, syncedFarther], duration: 200, title: "Song")?.id == 2)
    }

    @Test func nearestDurationWinsWithinATier() {
        let far = candidate(1, duration: 201.8, synced: Self.lrc)
        let near = candidate(2, duration: 200.4, synced: Self.lrc)
        let exact = candidate(3, duration: 200, synced: Self.lrc)
        #expect(LyricsMatch.best([far, near], duration: 200, title: "Song")?.id == 2)
        #expect(LyricsMatch.best([far, near, exact], duration: 200, title: "Song")?.id == 3)
        // Equal distance: the earlier one in the list.
        let a = candidate(4, duration: 199, synced: Self.lrc), b = candidate(5, duration: 201, synced: Self.lrc)
        #expect(LyricsMatch.best([b, a], duration: 200, title: "Song")?.id == 5)
    }

    @Test func durationWindowIsTwoSecondsOrThreePercent() {
        // 300 s track: 3 percent is 9 s.
        #expect(LyricsMatch.best([candidate(1, duration: 309, synced: Self.lrc)], duration: 300, title: "Song")?.id == 1)
        #expect(LyricsMatch.best([candidate(1, duration: 291, synced: Self.lrc)], duration: 300, title: "Song")?.id == 1)
        #expect(LyricsMatch.best([candidate(1, duration: 310, synced: Self.lrc)], duration: 300, title: "Song") == nil)
        // 40 s track: 3 percent is 1.2 s, so the 2 s floor applies.
        #expect(LyricsMatch.best([candidate(1, duration: 42, synced: Self.lrc)], duration: 40, title: "Song")?.id == 1)
        #expect(LyricsMatch.best([candidate(1, duration: 42.5, synced: Self.lrc)], duration: 40, title: "Song") == nil)
        // A candidate with no length cannot be checked against a known length.
        #expect(LyricsMatch.best([candidate(1, duration: 0, synced: Self.lrc)], duration: 200, title: "Song") == nil)
    }

    @Test func aWrongVersionIsRefusedEvenWhenItIsTheOnlyOne() {
        let live = candidate(1, "Song (Live)", duration: 260, synced: Self.lrc)
        #expect(LyricsMatch.best([live], duration: 200, title: "Song") == nil)
    }

    @Test func unknownDurationTakesOnlyAnExactTitle() {
        let other = candidate(1, "Song Two", duration: 200, synced: Self.lrc)
        let live = candidate(2, "Song (Live)", duration: 200, synced: Self.lrc)
        let exact = candidate(3, "SONG", duration: 311, plain: "words")
        #expect(LyricsMatch.best([other, live], duration: 0, title: "Song") == nil)
        #expect(LyricsMatch.best([other, live, exact], duration: 0, title: "Song")?.id == 3)
        // Synced still comes before plain among exact titles; order breaks the remaining tie.
        let exactSynced = candidate(4, "Song", duration: 150, synced: Self.lrc)
        let exactSyncedLater = candidate(5, "Song", duration: 151, synced: Self.lrc)
        #expect(LyricsMatch.best([exact, exactSyncedLater, exactSynced], duration: 0, title: "song")?.id == 5)
        // Only the title as the player reports it counts: a version suffix on either side is a different recording.
        let remastered = candidate(6, "Song - Remastered 2011", duration: 200, synced: Self.lrc)
        #expect(LyricsMatch.best([remastered], duration: 0, title: "Song") == nil)
        let single = candidate(7, "Song (Single Version)", duration: 200, synced: Self.lrc)
        #expect(LyricsMatch.best([single], duration: 0, title: "Song") == nil)
        #expect(LyricsMatch.best([single], duration: 0, title: "Song (Single Version)")?.id == 7)
        #expect(LyricsMatch.best([candidate(8, "Song", duration: 200, synced: Self.lrc)], duration: 0, title: "Song (Single Version)") == nil)
    }

    @Test func candidatesWithoutLyricsAreSkipped() {
        #expect(LyricsMatch.best([], duration: 200, title: "Song") == nil)
        #expect(LyricsMatch.best([candidate(1)], duration: 200, title: "Song") == nil)
        let empty = candidate(1, duration: 200)
        let plain = candidate(2, duration: 205, plain: "words")
        #expect(LyricsMatch.best([empty, plain], duration: 200, title: "Song")?.id == 2)
    }

    @Test func instrumentalRanksLastAndIsTakenWhenAlone() {
        let instrumental = candidate(1, duration: 200, instrumental: true)
        let plain = candidate(2, duration: 202, plain: "words")
        #expect(LyricsMatch.best([instrumental, plain], duration: 200, title: "Song")?.id == 2)
        #expect(LyricsMatch.best([instrumental], duration: 200, title: "Song")?.id == 1)
    }

    // MARK: The three requests

    private func items(_ url: URL?) -> [String: String] {
        guard let url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        return Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    private let version = LRCLIBQuery(artist: "Queen & David Bowie", title: "Under Pressure - Remastered 2011",
                                      album: "Hot Space", duration: 248.4)

    @Test func exactRequestIsTodaysStrictRequest() throws {
        let request = try #require(version.exactRequest)
        #expect(request.step == .exact)
        #expect(request.url == version.url)
        #expect(request.url.path == "/api/get")
        #expect(items(request.url) == ["artist_name": "Queen & David Bowie", "track_name": "Under Pressure - Remastered 2011",
                                      "album_name": "Hot Space", "duration": "248"])
    }

    @Test func cleanedRequestDropsTheAlbumAndKeepsTheDuration() throws {
        let request = try #require(version.cleanedRequest)
        #expect(request.step == .cleaned)
        #expect(request.url.path == "/api/get")
        // The title changed and the artist did not: the credited artist stays whole.
        #expect(items(request.url) == ["artist_name": "Queen & David Bowie", "track_name": "Under Pressure", "duration": "248"])
    }

    @Test func searchRequestCarriesOnlyTitleAndArtist() throws {
        let request = try #require(version.searchRequest)
        #expect(request.step == .search)
        #expect(request.url.path == "/api/search")
        #expect(items(request.url) == ["artist_name": "Queen", "track_name": "Under Pressure"])
    }

    @Test func requestsRunInOrder() {
        #expect(version.requests.map(\.step) == [.exact, .cleaned, .search])
    }

    @Test func cleanedRequestIsSkippedWhenCleanUpChangesNothing() {
        let plain = LRCLIBQuery(artist: "Adele", title: "Hello", album: "25", duration: 295)
        #expect(plain.cleanedRequest == nil)
        #expect(plain.requests.map(\.step) == [.exact, .search])
    }

    @Test func cleanedRequestRunsWhenOnlyAFeaturedArtistIsCredited() throws {
        let query = LRCLIBQuery(artist: "Artist A feat. Artist B", title: "Hello", album: "25", duration: 295)
        #expect(items(try #require(query.cleanedRequest).url) == ["artist_name": "Artist A", "track_name": "Hello", "duration": "295"])
    }

    @Test func cleanedRequestKeepsAGroupNameWhole() throws {
        // Only a feat. or ft. credit is cut from the artist; "&" and "," stay, so a band is not split in two.
        let table = ["Simon & Garfunkel", "Earth, Wind & Fire", "Tyler, The Creator", "Florence + the Machine"]
        for artist in table {
            let remaster = LRCLIBQuery(artist: artist, title: "September - Remastered", album: "", duration: 215)
            #expect(items(try #require(remaster.cleanedRequest).url)["artist_name"] == artist, "\(artist)")
            let plain = LRCLIBQuery(artist: artist, title: "September", album: "", duration: 215)
            #expect(plain.cleanedRequest == nil, "\(artist)")
        }
        let both = LRCLIBQuery(artist: "Earth, Wind & Fire ft. Someone", title: "September (Remastered)", duration: 215)
        #expect(items(try #require(both.cleanedRequest).url)["artist_name"] == "Earth, Wind & Fire")
    }

    @Test func lengthsLrclibCannotTakeAreNeverSent() throws {
        // /api/get answers 400 for a duration outside 1 to 3600: leave it out, and skip the step that needs it.
        let tooShort = LRCLIBQuery(artist: "Queen", title: "Under Pressure - Remastered 2011", album: "Hot Space", duration: 0.3)
        #expect(items(tooShort.exactRequest?.url)["duration"] == nil)
        #expect(tooShort.cleanedRequest == nil)
        #expect(tooShort.requests.map(\.step) == [.exact, .search])
        let mix = LRCLIBQuery(artist: "Some DJ", title: "Live Mix - Remastered", album: "Mixes", duration: 3720)
        #expect(items(mix.exactRequest?.url)["duration"] == nil)
        #expect(mix.cleanedRequest == nil)
        #expect(mix.requests.map(\.step) == [.exact, .search])
        for duration in [Double.nan, .infinity, -5, 1e12] {
            let odd = LRCLIBQuery(artist: "Queen", title: "Under Pressure - Remastered 2011", album: "Hot Space", duration: duration)
            #expect(items(odd.exactRequest?.url)["duration"] == nil, "\(duration)")
            #expect(odd.cleanedRequest == nil, "\(duration)")
        }
        // The edges that LRCLIB takes stay.
        #expect(items(LRCLIBQuery(artist: "A", title: "B", duration: 3600).exactRequest?.url)["duration"] == "3600")
        #expect(items(LRCLIBQuery(artist: "A", title: "B", duration: 0.5).exactRequest?.url)["duration"] == "1")
        #expect(items(LRCLIBQuery(artist: "A", title: "B", duration: 1).exactRequest?.url)["duration"] == "1")
        #expect(items(LRCLIBQuery(artist: "A", title: "B", duration: 0.4).exactRequest?.url)["duration"] == nil)
    }

    @Test func noLooseRequestWithoutADuration() {
        let query = LRCLIBQuery(artist: "Queen", title: "Under Pressure (Remastered 2011)", album: "Hot Space", duration: 0)
        #expect(query.requests.map(\.step) == [.exact, .search])
        #expect(items(query.exactRequest?.url)["duration"] == nil)
    }

    @Test func aTrackWithoutTitleOrArtistIsNotAsked() {
        #expect(LRCLIBQuery(artist: "", title: "Song", duration: 100).requests.isEmpty)
        #expect(LRCLIBQuery(artist: "Artist", title: "  ", duration: 100).requests.isEmpty)
    }

    @Test func plusSignsSurviveTheQueryString() throws {
        let query = LRCLIBQuery(artist: "Florence + the Machine", title: "Dog Days Are Over", album: "Lungs", duration: 252)
        let url = try #require(query.exactRequest?.url).absoluteString
        #expect(url.contains("Florence%20%2B%20the%20Machine"))
        #expect(items(query.exactRequest?.url)["artist_name"] == "Florence + the Machine")
    }

    @Test func cacheKeyIsUnchanged() {
        let query = LRCLIBQuery(artist: "M83", title: "Midnight City", album: "Hurry Up", duration: 243.4)
        #expect(query.cacheKey == LRCLIBQuery(artist: "m83", title: "MIDNIGHT CITY", album: "hurry up", duration: 243).cacheKey)
    }

    @Test func aBodyIsReadAccordingToItsStep() throws {
        let getBody = Data(#"{"id":1,"plainLyrics":"la la","syncedLyrics":null}"#.utf8)
        let exact = try #require(version.exactRequest)
        #expect(exact.result(from: getBody, query: version) == .plain("la la"))
        #expect(exact.result(from: Data(#"{"instrumental":true}"#.utf8), query: version) == .instrumental)
        #expect(exact.result(from: Data("junk".utf8), query: version) == LyricsResult.none)

        let search = try #require(version.searchRequest)
        let list = """
        [{"id":1,"trackName":"Under Pressure (Live)","artistName":"Queen","duration":250,"plainLyrics":null,"syncedLyrics":"[00:01.00] live"},
         {"id":2,"trackName":"Under Pressure","artistName":"Queen","duration":248,"plainLyrics":null,"syncedLyrics":"[00:01.00] studio"}]
        """
        #expect(search.result(from: Data(list.utf8), query: version) == .synced([LyricLine(time: 1, text: "studio")]))
        let wrongLength = #"[{"id":3,"trackName":"Under Pressure","artistName":"Queen","duration":400,"plainLyrics":"x"}]"#
        #expect(search.result(from: Data(wrongLength.utf8), query: version) == LyricsResult.none)
        #expect(search.result(from: Data("[]".utf8), query: version) == LyricsResult.none)
    }

    @Test func theSearchStepWithoutALengthTakesOnlyTheTitleAsPlayed() throws {
        let query = LRCLIBQuery(artist: "Artist", title: "Song (Single Version)", album: "", duration: 0)
        let search = try #require(query.searchRequest)
        let list = """
        [{"id":1,"trackName":"Song","artistName":"Artist","duration":240,"plainLyrics":null,"syncedLyrics":"[00:01.00] album"},
         {"id":2,"trackName":"Song (Single Version)","artistName":"Artist","duration":200,"plainLyrics":null,"syncedLyrics":"[00:01.00] single"}]
        """
        #expect(search.result(from: Data(list.utf8), query: query) == .synced([LyricLine(time: 1, text: "single")]))
        let onlyAlbum = #"[{"id":1,"trackName":"Song","artistName":"Artist","duration":240,"plainLyrics":"x"}]"#
        #expect(search.result(from: Data(onlyAlbum.utf8), query: query) == LyricsResult.none)
    }

    // MARK: HTTP status

    @Test func statusCodesMapToOutcomes() {
        #expect(LyricsStatus.outcome(status: 200, retryAfter: nil) == .found)
        #expect(LyricsStatus.outcome(status: 404, retryAfter: nil) == .notFound)
        #expect(LyricsStatus.outcome(status: 429, retryAfter: nil) == .failed(retryAfter: nil))
        #expect(LyricsStatus.outcome(status: 429, retryAfter: 120) == .failed(retryAfter: 120))
        for status in [500, 502, 503, 504, 599] {
            #expect(LyricsStatus.outcome(status: status, retryAfter: 5) == .failed(retryAfter: 5), "\(status)")
        }
        // A request the service refuses as invalid (400, 401, 403, 410, 422...) is an answer for this step: it says
        // nothing about the service being down, so it never starts the shared wait.
        for status in [400, 401, 403, 410, 422, 451] {
            #expect(LyricsStatus.outcome(status: status, retryAfter: 5) == .notFound, "\(status)")
        }
        // Timeouts and rate limits are failures.
        #expect(LyricsStatus.outcome(status: 408, retryAfter: nil) == .failed(retryAfter: nil))
        // Anything unexpected is a failure, never a cached "no lyrics".
        for status in [0, -1, 100, 204, 301, 302] {
            #expect(LyricsStatus.outcome(status: status, retryAfter: nil) == .failed(retryAfter: nil), "\(status)")
        }
        // The wait is only carried by failures.
        #expect(LyricsStatus.outcome(status: 404, retryAfter: 10) == .notFound)
        #expect(LyricsStatus.outcome(status: 200, retryAfter: 10) == .found)
    }

    @Test func retryAfterHeaderParses() {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        #expect(LyricsStatus.retryAfter(header: "120", now: now) == 120)
        #expect(LyricsStatus.retryAfter(header: " 7 ", now: now) == 7)
        #expect(LyricsStatus.retryAfter(header: "0", now: now) == 0)
        #expect(LyricsStatus.retryAfter(header: nil, now: now) == nil)
        #expect(LyricsStatus.retryAfter(header: "", now: now) == nil)
        #expect(LyricsStatus.retryAfter(header: "soon", now: now) == nil)
        #expect(LyricsStatus.retryAfter(header: "-5", now: now) == nil)
        // An HTTP date is read relative to now: Wed, 21 Oct 2026 07:28:00 GMT.
        let stamp = Date(timeIntervalSince1970: 1_792_567_680)
        #expect(LyricsStatus.retryAfter(header: "Wed, 21 Oct 2026 07:28:00 GMT", now: stamp.addingTimeInterval(-60)) == 60)
        #expect(LyricsStatus.retryAfter(header: "Wed, 21 Oct 2026 07:28:00 GMT", now: stamp.addingTimeInterval(60)) == 0)
    }

    // MARK: Back-off

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func backoffStartsOpen() {
        let backoff = LyricsBackoff()
        #expect(backoff.failures == 0 && backoff.blockedUntil == nil)
        #expect(backoff.canAsk(now: t0))
        #expect(backoff.remaining(now: t0) == 0)
    }

    @Test func backoffDoublesFromThirtySecondsToAFifteenMinuteCeiling() {
        var backoff = LyricsBackoff()
        var waits: [TimeInterval] = []
        for _ in 0..<8 {
            backoff.recordFailure(now: t0, retryAfter: nil)
            waits.append(backoff.blockedUntil!.timeIntervalSince(t0))
        }
        #expect(waits == [30, 60, 120, 240, 480, 900, 900, 900])
        #expect(backoff.failures == 8)
    }

    @Test func backoffBlocksUntilTheWaitEnds() {
        var backoff = LyricsBackoff()
        backoff.recordFailure(now: t0, retryAfter: nil)
        #expect(!backoff.canAsk(now: t0))
        #expect(!backoff.canAsk(now: t0.addingTimeInterval(29.9)))
        #expect(backoff.remaining(now: t0.addingTimeInterval(10)) == 20)
        #expect(backoff.canAsk(now: t0.addingTimeInterval(30)))
        #expect(backoff.canAsk(now: t0.addingTimeInterval(500)))
    }

    @Test func retryAfterReplacesTheDelayForThatFailure() {
        var backoff = LyricsBackoff()
        backoff.recordFailure(now: t0, retryAfter: 120)
        #expect(backoff.blockedUntil == t0.addingTimeInterval(120))
        // The failure still counts, so the next plain failure is the second step of the sequence.
        backoff.recordFailure(now: t0, retryAfter: nil)
        #expect(backoff.blockedUntil == t0.addingTimeInterval(60))
        backoff.recordFailure(now: t0, retryAfter: 5)
        #expect(backoff.blockedUntil == t0.addingTimeInterval(5))
        // A Retry-After above the ceiling is honoured, up to an hour.
        backoff.recordFailure(now: t0, retryAfter: 1800)
        #expect(backoff.blockedUntil == t0.addingTimeInterval(1800))
        backoff.recordFailure(now: t0, retryAfter: 86_400)
        #expect(backoff.blockedUntil == t0.addingTimeInterval(3600))
    }

    @Test func aZeroOrNegativeRetryAfterIsIgnored() {
        var backoff = LyricsBackoff()
        backoff.recordFailure(now: t0, retryAfter: 0)
        #expect(backoff.blockedUntil == t0.addingTimeInterval(30))
        backoff.recordFailure(now: t0, retryAfter: -4)
        #expect(backoff.blockedUntil == t0.addingTimeInterval(60))
    }

    @Test func successClearsTheWait() {
        var backoff = LyricsBackoff()
        backoff.recordFailure(now: t0, retryAfter: nil)
        backoff.recordFailure(now: t0, retryAfter: nil)
        backoff.recordSuccess()
        #expect(backoff.failures == 0 && backoff.blockedUntil == nil)
        #expect(backoff.canAsk(now: t0))
        backoff.recordFailure(now: t0, retryAfter: nil)
        #expect(backoff.blockedUntil == t0.addingTimeInterval(30))
    }
}
