import Foundation
import Testing
@testable import ZeusCore

@Suite struct BrowserMediaTests {
    // MARK: Fixtures

    private func itemJSON(_ overrides: [String: JSONValue] = [:]) -> JSONValue {
        var object: [String: JSONValue] = [
            "tabId": .number(3), "documentId": .string("doc-1"), "url": .string("https://music.example.com/watch?v=1"),
            "audible": .bool(true), "title": .string("Song"), "artist": .string("Band"), "album": .string("Record"),
            "artworkURL": .string("https://img.example.com/cover.jpg"), "playbackState": .string("playing"),
            "currentTime": .number(42), "duration": .number(200), "playbackRate": .number(1),
            "paused": .bool(false), "seekable": .bool(true), "fingerprint": .string("ab12cd34"),
        ]
        for (key, value) in overrides { object[key] = value }
        return .object(object)
    }

    private func reply(_ items: [JSONValue], gone: [JSONValue] = [], stale: Bool? = nil) -> JSONValue {
        var object: [String: JSONValue] = ["items": .array(items), "gone": .array(gone)]
        if let stale { object["stale"] = .bool(stale) }
        return .object(object)
    }

    private func sample(_ overrides: [String: JSONValue] = [:]) throws -> BrowserMediaItem {
        try #require(BrowserMediaState.parse(reply([itemJSON(overrides)]))?.items.first)
    }

    // MARK: Parsing

    @Test func aFullReplyBecomesAnItem() throws {
        let item = try sample()
        #expect(item.tabID == 3 && item.documentID == "doc-1")
        #expect(item.host == "music.example.com")
        #expect(item.title == "Song" && item.artist == "Band" && item.album == "Record")
        #expect(item.artworkURL == URL(string: "https://img.example.com/cover.jpg"))
        #expect(item.element.currentTime == 42 && item.element.duration == 200)
        #expect(item.element.playbackRate == 1 && !item.element.paused && item.element.seekable)
        #expect(item.element.fingerprint == "ab12cd34")
    }

    @Test func aTabWithoutMetadataKeepsTheTitleTheWorkerSentAndHasNoArtistSoNoLyrics() throws {
        let item = try sample(["artist": .string(""), "album": .string(""), "title": .string("Tab title")])
        let playing = BrowserMediaRules.nowPlaying(item, anchor: Date(timeIntervalSince1970: 100))
        #expect(playing.title == "Tab title" && playing.artist.isEmpty)
        #expect(!playing.capabilities.contains(.lyrics))
    }

    @Test func aLiveStreamHasNoLengthAndNoScrub() throws {
        let item = try sample(["duration": .null, "seekable": .bool(false)])
        #expect(item.element.duration == 0)
        let playing = BrowserMediaRules.nowPlaying(item, anchor: Date())
        #expect(playing.duration == 0)
        #expect(!playing.capabilities.contains(.seek))
    }

    @Test func badNumbersRejectTheItemAndKeepTheRest() throws {
        let bad: [[String: JSONValue]] = [
            ["currentTime": .number(-1)], ["currentTime": .number(.infinity)], ["currentTime": .number(.nan)],
            ["duration": .number(-5)], ["playbackRate": .number(-1)], ["playbackRate": .number(.infinity)],
            ["tabId": .number(-1)], ["tabId": .number(1.5)], ["currentTime": .string("12")],
        ]
        for overrides in bad {
            let state = try #require(BrowserMediaState.parse(reply([itemJSON(overrides), itemJSON(["tabId": .number(9)])])))
            #expect(state.items.map(\.tabID) == [9], "\(overrides)")
        }
    }

    @Test func aReplyWithoutAnItemListIsMalformed() {
        #expect(BrowserMediaState.parse(.object([:])) == nil)
        #expect(BrowserMediaState.parse(.string("x")) == nil)
        #expect(BrowserMediaState.parse(.object(["items": .string("x")])) == nil)
    }

    @Test func itemsAndStringsAreCapped() throws {
        let long = String(repeating: "a", count: 900)
        let item = try sample(["title": .string(long), "artist": .string(long), "album": .string(long)])
        #expect(item.title.count == BrowserMediaRules.maximumText)
        #expect(item.artist.count == BrowserMediaRules.maximumText && item.album.count == BrowserMediaRules.maximumText)
        let many = (0..<9).map { itemJSON(["tabId": .number(Double($0))]) }
        #expect(try #require(BrowserMediaState.parse(reply(many))).items.count == BrowserMediaRules.maximumItems)
        let gone = (0..<99).map { JSONValue.object(["tabId": .number(Double($0)), "documentId": .string("d")]) }
        #expect(try #require(BrowserMediaState.parse(reply([], gone: gone))).gone.count <= 16)
    }

    @Test func anItemWithoutATitleOrIdentityIsDropped() throws {
        for overrides: [String: JSONValue] in [["title": .string("")], ["documentId": .string("")], ["fingerprint": .string("")],
                                               ["url": .string("")]] {
            #expect(try #require(BrowserMediaState.parse(reply([itemJSON(overrides)]))).items.isEmpty, "\(overrides)")
        }
    }

    @Test func onlyAWebPageIsAnItemNeverAFileOrAPrivateWindow() throws {
        for url in ["file:///Users/me/saved/page.html", "ftp://x.example/a", "chrome://settings", "blob:https://x.example/1", "data:text/html,hi"] {
            #expect(try #require(BrowserMediaState.parse(reply([itemJSON(["url": .string(url)])]))).items.isEmpty, "\(url)")
        }
        #expect(try #require(BrowserMediaState.parse(reply([itemJSON(["incognito": .bool(true)])]))).items.isEmpty)
        #expect(try #require(BrowserMediaState.parse(reply([itemJSON(["incognito": .bool(false)])]))).items.count == 1)
    }

    @Test func theCoverMustBeAnHttpsLinkOfReasonableLength() throws {
        for link in ["data:image/png;base64,AAAA", "blob:https://x.example/1", "http://img.example.com/a.jpg", "javascript:alert(1)",
                     "https://img.example.com/" + String(repeating: "a", count: 2100), "https://"] {
            #expect(try sample(["artworkURL": .string(link)]).artworkURL == nil, "\(link.prefix(40))")
        }
        #expect(try sample(["artworkURL": .null]).artworkURL == nil)
    }

    @Test func goneAndStaleAreRead() throws {
        let state = try #require(BrowserMediaState.parse(reply([], gone: [.object(["tabId": .number(4), "documentId": .string("d4")])], stale: true)))
        #expect(state.stale)
        #expect(state.gone == [BrowserMediaTarget(tabID: 4, documentID: "d4")])
    }

    // MARK: Item to now playing

    @Test func aBrowserItemIsABrowserSourceThatKeepsNothingOnDisk() throws {
        let item = try sample()
        let playing = BrowserMediaRules.nowPlaying(item, anchor: Date(timeIntervalSince1970: 100))
        #expect(playing.source == .browser(BrowserMediaKey(tabID: 3, documentID: "doc-1", host: "music.example.com", fingerprint: "ab12cd34")))
        #expect(!playing.source.persistsDerivedData)
        #expect(playing.isPlaying && playing.position == 42 && playing.duration == 200 && playing.rate == 1)
        #expect(playing.positionAt == Date(timeIntervalSince1970: 100))
        #expect(playing.artworkURL == item.artworkURL)
        #expect(try sample(["paused": .bool(true)]).element.paused)
        #expect(!BrowserMediaRules.nowPlaying(try sample(["paused": .bool(true)]), anchor: Date()).isPlaying)
    }

    // MARK: Between polls

    @Test func positionAdvancesByRateWhileItPlaysAndIsClamped() {
        #expect(BrowserMediaRules.extrapolate(position: 10, rate: 1, duration: 100, isPlaying: true, elapsed: 3) == 13)
        #expect(BrowserMediaRules.extrapolate(position: 10, rate: 2, duration: 100, isPlaying: true, elapsed: 3) == 16)
        #expect(BrowserMediaRules.extrapolate(position: 10, rate: 0, duration: 100, isPlaying: true, elapsed: 3) == 10)
        #expect(BrowserMediaRules.extrapolate(position: 10, rate: 1, duration: 100, isPlaying: false, elapsed: 3) == 10)
        #expect(BrowserMediaRules.extrapolate(position: 99, rate: 1, duration: 100, isPlaying: true, elapsed: 30) == 100)
        #expect(BrowserMediaRules.extrapolate(position: 99, rate: 1, duration: 0, isPlaying: true, elapsed: 30) == 129)
    }

    @Test func aSampleReanchorsOnlyPastThreeQuartersOfASecondOfError() {
        #expect(!BrowserMediaRules.shouldReanchor(predicted: 50, observed: 50.7))
        #expect(!BrowserMediaRules.shouldReanchor(predicted: 50, observed: 49.3))
        #expect(BrowserMediaRules.shouldReanchor(predicted: 50, observed: 50.8))
        #expect(BrowserMediaRules.shouldReanchor(predicted: 50, observed: 20))
    }

    @Test func aSampleInsideTheToleranceLeavesTheHubAnEqualValue() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let first = BrowserMediaRules.nowPlaying(try sample(), anchor: start)
        let later = start.addingTimeInterval(2)
        let near = BrowserMediaRules.nowPlaying(try sample(["currentTime": .number(44.3)]), anchor: later)
        #expect(BrowserMediaRules.merged(previous: first, sample: near) == first)
        let seeked = BrowserMediaRules.nowPlaying(try sample(["currentTime": .number(120)]), anchor: later)
        #expect(BrowserMediaRules.merged(previous: first, sample: seeked) == seeked)
        let paused = BrowserMediaRules.nowPlaying(try sample(["currentTime": .number(44), "paused": .bool(true)]), anchor: later)
        #expect(BrowserMediaRules.merged(previous: first, sample: paused) == paused)
        let faster = BrowserMediaRules.nowPlaying(try sample(["currentTime": .number(44), "playbackRate": .number(2)]), anchor: later)
        #expect(BrowserMediaRules.merged(previous: first, sample: faster) == faster)
        #expect(BrowserMediaRules.merged(previous: nil, sample: near) == near)
    }

    // MARK: Poll delay

    @Test func noPollingUnderAPinOrWithNoOutputAndNothingShown() {
        var context = BrowserPollContext(followsAny: false, outputRunning: true, browserShown: true, browserShownPlaying: true)
        #expect(BrowserMediaRules.pollDelay(context) == nil)
        context = BrowserPollContext(followsAny: true)
        #expect(BrowserMediaRules.pollDelay(context) == nil)
    }

    @Test func twoSecondsWhileATabPlaysElseFive() {
        #expect(BrowserMediaRules.pollDelay(.init(followsAny: true, browserShown: true, browserShownPlaying: true)) == 2)
        #expect(BrowserMediaRules.pollDelay(.init(followsAny: true, outputRunning: true)) == 5)
        #expect(BrowserMediaRules.pollDelay(.init(followsAny: true, browserShown: true, browserShownPlaying: false)) == 5)
        #expect(BrowserMediaRules.pollDelay(.init(followsAny: true, pausedKnownWithMusicPageOpen: true)) == 5)
    }

    // MARK: Commands

    @Test func playPauseAndSeekMapAndNextAndPreviousDoNot() throws {
        let item = try sample()
        #expect(BrowserMediaRules.command(for: .play, seconds: nil, item: item)?.action == .play)
        #expect(BrowserMediaRules.command(for: .pause, seconds: nil, item: item)?.action == .pause)
        #expect(BrowserMediaRules.command(for: .playPause, seconds: nil, item: item)?.action == .pause)
        let paused = try sample(["paused": .bool(true)])
        #expect(BrowserMediaRules.command(for: .playPause, seconds: nil, item: paused)?.action == .play)
        #expect(BrowserMediaRules.command(for: .next, seconds: nil, item: item) == nil)
        #expect(BrowserMediaRules.command(for: .previous, seconds: nil, item: item) == nil)
        #expect(BrowserMediaRules.command(for: .toggleShuffle, seconds: nil, item: item) == nil)
        #expect(BrowserMediaRules.command(for: .cycleRepeat, seconds: nil, item: item) == nil)
        #expect(BrowserMediaRules.command(for: .open, seconds: nil, item: item) == nil)
    }

    @Test func aSeekIsClampedShortOfTheEndAndNeedsATarget() throws {
        let item = try sample()
        #expect(BrowserMediaRules.command(for: .seek, seconds: 500, item: item)?.seconds == 199.5)
        #expect(BrowserMediaRules.command(for: .seek, seconds: -4, item: item)?.seconds == 0)
        #expect(BrowserMediaRules.command(for: .seek, seconds: 60, item: item)?.seconds == 60)
        #expect(BrowserMediaRules.command(for: .seek, seconds: nil, item: item) == nil)
        #expect(BrowserMediaRules.command(for: .seek, seconds: .nan, item: item) == nil)
        let live = try sample(["duration": .null, "seekable": .bool(false)])
        #expect(BrowserMediaRules.command(for: .seek, seconds: 10, item: live) == nil)
    }

    @Test func theTargetJSONCarriesTheDocumentTheAddressAndTheFingerprintAndNeedsNoActiveTab() throws {
        let command = try #require(BrowserMediaRules.command(for: .seek, seconds: 60, item: try sample()))
        let params = command.params()
        #expect(params["action"] == .string("seek") && params["seconds"] == .number(60))
        #expect(params["fingerprint"] == .string("ab12cd34"))
        let target = try #require(params["pageTarget"])
        #expect(target["tabId"] == .number(3) && target["documentId"] == .string("doc-1"))
        #expect(target["url"] == .string("https://music.example.com/watch?v=1"))
        #expect(target["requiresActive"] == .bool(false))
        let play = try #require(BrowserMediaRules.command(for: .play, seconds: nil, item: try sample())).params()
        #expect(play["seconds"] == nil)
    }

    // MARK: Calls

    @Test func whileACallRunsInABrowserNoItemIsShownAndNoCommandIsSent() throws {
        let item = try sample()
        #expect(BrowserMediaRules.usable([item], callPresent: false) == [item])
        #expect(BrowserMediaRules.usable([item], callPresent: true).isEmpty)
        #expect(BrowserMediaRules.command(for: .pause, seconds: nil, item: item, callPresent: true) == nil)
        #expect(BrowserMediaRules.command(for: .pause, seconds: nil, item: item, callPresent: false) != nil)
    }

    // MARK: Version and failures

    @Test func theExtensionNeedsVersionZeroFiveOrLater() {
        #expect(BrowserMediaRules.extensionSupportsMedia(version: "0.5.0"))
        #expect(BrowserMediaRules.extensionSupportsMedia(version: "0.5.1"))
        #expect(BrowserMediaRules.extensionSupportsMedia(version: "0.10.0"))
        #expect(BrowserMediaRules.extensionSupportsMedia(version: "1.0"))
        #expect(!BrowserMediaRules.extensionSupportsMedia(version: "0.4.0"))
        #expect(!BrowserMediaRules.extensionSupportsMedia(version: "0.4.9"))
        #expect(!BrowserMediaRules.extensionSupportsMedia(version: nil))
        #expect(!BrowserMediaRules.extensionSupportsMedia(version: ""))
        #expect(!BrowserMediaRules.extensionSupportsMedia(version: "five"))
    }

    @Test func failureCodesAreTold() {
        #expect(BrowserMediaFailure(code: "stale_target") == .staleTarget)
        #expect(BrowserMediaFailure(code: "not_supported") == .notSupported)
        #expect(BrowserMediaFailure(code: "blocked_by_page") == .blockedByPage)
        #expect(BrowserMediaFailure(code: "unknown_type") == .notSupported)
        #expect(BrowserMediaFailure(code: "anything else") == .other)
    }
}
