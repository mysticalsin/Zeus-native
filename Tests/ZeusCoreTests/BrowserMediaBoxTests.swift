import Foundation
import Testing
@testable import ZeusCore

@Suite("Browser media box")
struct BrowserMediaBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(BrowserMediaBox.blankScalars.contains(" "))
        #expect(BrowserMediaBox.blankScalars.contains("\t"))
        #expect(BrowserMediaBox.blankScalars.contains("\n"))
        #expect(BrowserMediaBox.blankScalars.contains("\r"))
        #expect(BrowserMediaBox.blankScalars.contains("\u{00A0}"))
        #expect(!BrowserMediaBox.blankScalars.contains("\u{200B}"))
        #expect(!BrowserMediaBox.titleIsVisible(" \t\n\r\u{00A0}"))
        #expect(!BrowserMediaBox.titleIsVisible(""))
        #expect(BrowserMediaBox.titleIsVisible("\u{200B}"))
        #expect(BrowserMediaBox.titleIsVisible(" \u{200B} "))
        #expect(BrowserMediaBox.titleIsVisible("Song"))
    }

    @Test func aReplyKeepsAZeroWidthTitleAndDropsABlankOne() throws {
        let kept = try #require(BrowserMediaState.parse(reply([itemJSON(["title": .string("\u{200B}")])]))?.items.first)
        #expect(kept.title == "\u{200B}")
        #expect(try #require(BrowserMediaState.parse(reply([itemJSON(["title": .string(" \n\t")])]))).items.isEmpty)
        #expect(try #require(BrowserMediaState.parse(reply([itemJSON(["title": .string("\u{00A0}")])]))).items.isEmpty)
    }

    @Test func theBoxOwnsThePaceAndTheReanchor() {
        #expect(BrowserMediaBox.playingDelay == 2)
        #expect(BrowserMediaBox.idleDelay == 5)
        #expect(BrowserMediaBox.reanchorTolerance == 0.75)
        #expect(BrowserMediaBox.maximumItems == 4)
        #expect(BrowserMediaBox.pollDelay(.init(followsAny: true, browserShown: true, browserShownPlaying: true)) == 2)
        #expect(BrowserMediaBox.pollDelay(.init(followsAny: true, outputRunning: true)) == 5)
        #expect(BrowserMediaBox.pollDelay(.init(followsAny: false, outputRunning: true)) == nil)
        #expect(!BrowserMediaBox.shouldReanchor(predicted: 50, observed: 50.75))
        #expect(BrowserMediaBox.shouldReanchor(predicted: 50, observed: 50.76))
    }

    @Test func playbackDoesNotMoveBackward() {
        #expect(BrowserMediaBox.extrapolate(position: 10, rate: 1, duration: 100, isPlaying: true, elapsed: -4) == 10)
        #expect(BrowserMediaBox.extrapolate(position: 10, rate: -2, duration: 100, isPlaying: true, elapsed: 4) == 10)
        #expect(BrowserMediaBox.extrapolate(position: 10, rate: 1, duration: 100, isPlaying: false, elapsed: 4) == 10)
        #expect(BrowserMediaBox.extrapolate(position: 99, rate: 1, duration: 100, isPlaying: true, elapsed: 5) == 100)
        #expect(BrowserMediaBox.extrapolate(position: 10, rate: 1, duration: 0, isPlaying: true, elapsed: 5) == 15)
    }

    @Test func anExtensionVersionIsComparedByNumbers() {
        #expect(BrowserMediaBox.minimumVersion == [0, 5, 0])
        #expect(BrowserMediaBox.extensionSupportsMedia(version: "0.5"))
        #expect(BrowserMediaBox.extensionSupportsMedia(version: "0.5.0.1"))
        #expect(!BrowserMediaBox.extensionSupportsMedia(version: "0.4.9"))
        #expect(!BrowserMediaBox.extensionSupportsMedia(version: "0..5"))
        #expect(!BrowserMediaBox.extensionSupportsMedia(version: "1.2.3.4.5"))
        #expect(!BrowserMediaBox.extensionSupportsMedia(version: nil))
        #expect(!BrowserMediaBox.extensionSupportsMedia(version: " "))
    }

    @Test func aCoverLinkIsHttpsWithAHost() {
        #expect(BrowserMediaBox.artworkURL("https://img.example.com/a.jpg") == URL(string: "https://img.example.com/a.jpg"))
        #expect(BrowserMediaBox.artworkURL("http://img.example.com/a.jpg") == nil)
        #expect(BrowserMediaBox.artworkURL("https://") == nil)
        #expect(BrowserMediaBox.artworkURL(nil) == nil)
        #expect(BrowserMediaBox.artworkURL(" \u{200B}") == nil)
    }

    @Test func aSeekStopsShortOfTheEndAndACallSendsNothing() throws {
        let item = try sample()
        #expect(BrowserMediaBox.command(for: .seek, seconds: 500, item: item)?.seconds == 199.5)
        #expect(BrowserMediaBox.command(for: .seek, seconds: .nan, item: item) == nil)
        #expect(BrowserMediaBox.command(for: .next, seconds: nil, item: item) == nil)
        #expect(BrowserMediaBox.command(for: .pause, seconds: nil, item: item, callPresent: true) == nil)
        #expect(BrowserMediaBox.usable([item], callPresent: true).isEmpty)
        #expect(BrowserMediaBox.usable([item], callPresent: false) == [item])
    }

    private func itemJSON(_ overrides: [String: JSONValue] = [:]) -> JSONValue {
        var object: [String: JSONValue] = [
            "tabId": .number(3), "documentId": .string("doc-1"), "url": .string("https://music.example.com/watch?v=1"),
            "audible": .bool(true), "title": .string("Song"), "artist": .string("Band"), "album": .string("Record"),
            "currentTime": .number(42), "duration": .number(200), "playbackRate": .number(1),
            "paused": .bool(false), "seekable": .bool(true), "fingerprint": .string("ab12cd34"),
        ]
        for (key, value) in overrides { object[key] = value }
        return .object(object)
    }

    private func reply(_ items: [JSONValue]) -> JSONValue {
        .object(["items": .array(items)])
    }

    private func sample() throws -> BrowserMediaItem {
        try #require(BrowserMediaState.parse(reply([itemJSON()]))?.items.first)
    }
}
