import Foundation
import Testing
@testable import ZeusCore

/// Lyric input is untrusted: a crowd-sourced lyric body and a player's title must never stall the main actor.
/// The hostile inputs are 10,000 to 20,000 characters; the budgets are generous next to the linear cost and far
/// below the seconds the quadratic scans took.
@Suite struct LyricsHardeningTests {
    private static let budget: Duration = .seconds(1)

    private func elapsed(_ work: () -> Void) -> Duration {
        let clock = ContinuousClock()
        return clock.measure(work)
    }

    // MARK: Word tags in lyric text

    @Test func aLongRunOfOpeningBracketsIsScannedInLinearTime() {
        let hostile = String(repeating: "<", count: 20_000)
        var result = ""
        let time = elapsed { result = LRC.strippingWordTags(hostile[...]) }
        #expect(result == hostile)
        #expect(time < Self.budget)
    }

    @Test func aRunOfOpeningBracketsWithOneClosingBracketIsScannedInLinearTime() {
        let hostile = String(repeating: "<", count: 20_000) + ">"
        var result = ""
        let time = elapsed { result = LRC.strippingWordTags(hostile[...]) }
        #expect(result == hostile)
        #expect(time < Self.budget)
    }

    @Test func aHostileLineParsesFast() {
        let body = "[00:01.00]" + String(repeating: "<", count: 20_000) + "\n[00:02.00]after"
        var lines: [LyricLine] = []
        let time = elapsed { lines = LRC.parse(body) }
        #expect(lines.count == 2)
        #expect(lines.last == LyricLine(time: 2, text: "after"))
        #expect(time < Self.budget)
    }

    @Test func realWordTagsAreStillStrippedAndLongOnesAreNotTimestamps() {
        #expect(LRC.strippingWordTags("a <00:01.00> b <1:02.5>c"[...]) == "a b c")
        // No timestamp is longer than a few characters: a tag with a long digit run stays as text.
        let long = "<" + String(repeating: "0", count: 40) + ":01>"
        #expect(LRC.strippingWordTags("x\(long)y"[...]) == "x\(long)y")
    }

    // MARK: Title clean-up

    @Test func aTitleWithAHugeWhitespaceRunIsCleanedFast() {
        let hostile = "a" + String(repeating: " ", count: 10_000) + "b"
        var result = ""
        let time = elapsed { result = LyricsTitle.stripped(hostile) }
        #expect(result == hostile)
        #expect(time < Self.budget)
    }

    @Test func aTitleWithMixedWhitespaceAndABracketIsCleanedFast() {
        let hostile = "a" + String(repeating: " \t\n", count: 3_500) + "(feat. b"
        var result = ""
        let time = elapsed { result = LyricsTitle.stripped(hostile) }
        #expect(result == hostile)
        #expect(time < Self.budget)
    }

    @Test func aModerateWhitespaceRunIsCollapsedBeforeTheSuffixRulesRun() {
        let title = "Song" + String(repeating: " ", count: 400) + "(Remastered)"
        var result = ""
        let time = elapsed { result = LyricsTitle.stripped(title) }
        #expect(result == "Song")
        #expect(time < Self.budget)
    }

    @Test func buildingTheRequestsForAHostileTitleIsFast() {
        let query = LRCLIBQuery(artist: "Artist", title: "a" + String(repeating: " ", count: 10_000) + "b", duration: 200)
        var count = 0
        let time = elapsed { count = query.requests.count }
        #expect(count == 2)
        #expect(time < Self.budget)
    }

    // MARK: Search candidates are checked on title when the length is known

    private func candidate(_ id: Int, _ title: String, duration: Double) -> LyricsCandidate {
        LyricsCandidate(id: id, title: title, artist: "Artist", duration: duration, instrumental: false,
                        syncedText: "[00:01.00] one\n[00:02.00] two", plainText: nil)
    }

    @Test func aLiveTakeInsideTheWindowIsRefusedEvenWhenItIsNearer() {
        let live = candidate(1, "Song (Live at Wembley)", duration: 251)
        let studio = candidate(2, "Song", duration: 254)
        #expect(LyricsMatch.best([live, studio], duration: 250, title: "Song")?.id == 2)
        #expect(LyricsMatch.best([live], duration: 250, title: "Song") == nil)
    }

    @Test func aRemasterTagOnEitherSideStillMatchesWhenTheLengthIsKnown() {
        #expect(LyricsMatch.best([candidate(1, "Song - 2011 Remaster", duration: 200)], duration: 200, title: "Song")?.id == 1)
        #expect(LyricsMatch.best([candidate(2, "Song", duration: 200)], duration: 200, title: "Song (Remastered)")?.id == 2)
        #expect(LyricsMatch.best([candidate(3, "SONG", duration: 200)], duration: 200, title: "song")?.id == 3)
    }

    @Test func aCurlyApostropheDoesNotHideAnOtherwiseCorrectEntry() {
        #expect(LyricsMatch.best([candidate(1, "Don\u{2019}t Stop", duration: 200)], duration: 200, title: "Don't Stop")?.id == 1)
        #expect(LyricsMatch.best([candidate(2, "Don't Stop", duration: 200)], duration: 200, title: "Don\u{2019}t Stop")?.id == 2)
    }

    @Test func aDifferentTitleInsideTheWindowIsRefused() {
        #expect(LyricsMatch.best([candidate(1, "Another Song", duration: 200)], duration: 200, title: "Song") == nil)
    }

    // MARK: Misses cached by the old lookup

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("lyr-\(UUID())")
    }

    @Test func aMissWrittenByTheOldLookupIsIgnored() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let query = LRCLIBQuery(artist: "David Bowie", title: "Heroes - 2017 Remaster", duration: 370)
        let now = Date()
        // The old entry format had no version field.
        let old = #"{"kind":"none","fetchedAt":\#(now.addingTimeInterval(-60).timeIntervalSinceReferenceDate)}"#
        try Data(old.utf8).write(to: dir.appendingPathComponent(query.cacheKey + ".json"))
        let cache = LyricsCache(directory: dir)
        #expect(cache.load(query, now: now) == nil)
        // A miss written now is kept for its lifetime, as before.
        cache.save(.none, for: query, now: now)
        #expect(cache.load(query, now: now.addingTimeInterval(60)) == LyricsResult.none)
        #expect(cache.load(query, now: now.addingTimeInterval(5 * 86400)) == nil)
    }

    @Test func answersWrittenByTheOldLookupAreKept() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let query = LRCLIBQuery(artist: "A", title: "B", duration: 100)
        let old = #"{"kind":"plain","plain":"la la","fetchedAt":0}"#
        try Data(old.utf8).write(to: dir.appendingPathComponent(query.cacheKey + ".json"))
        #expect(LyricsCache(directory: dir).load(query) == .plain("la la"))
    }
}
