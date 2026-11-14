import Foundation
import Testing
@testable import ZeusCore

/// The size bounds on lyric replies, cached answers and what the rows draw (ZeusCore's `LyricsLimits`).
@Suite struct LyricsLimitsTests {
    // MARK: Reply size

    @Test func aReplyOverTheLimitIsAFailureNotAnAnswer() {
        let limit = LyricsLimits.maxReplyBytes
        #expect(LyricsStatus.outcome(status: 200, retryAfter: nil, bodyBytes: limit) == .found)
        #expect(LyricsStatus.outcome(status: 200, retryAfter: nil, bodyBytes: limit + 1) == .failed(retryAfter: nil))
        #expect(LyricsStatus.outcome(status: 200, retryAfter: 12, bodyBytes: limit + 1) == .failed(retryAfter: 12))
        // A refusal stays a refusal, and a reply without a size is judged by its status alone.
        #expect(LyricsStatus.outcome(status: 404, retryAfter: nil, bodyBytes: limit + 1) == .notFound)
        #expect(LyricsStatus.outcome(status: 200, retryAfter: nil) == .found)
    }

    // MARK: What the views draw

    @Test func aLyricKeepsOnlyTheLinesTheViewsCanUse() {
        let body = (0..<(LyricsLimits.maxLines + 500)).map { "[\(String(format: "%02d", $0 / 60)):\(String(format: "%02d", $0 % 60)).00] line \($0)" }
            .joined(separator: "\n")
        let lines = LRC.parse(body)
        #expect(lines.count == LyricsLimits.maxLines)
        #expect(lines.first?.text == "line 0")
    }

    @Test func aLongLineIsCutAndAShortOneIsNot() {
        let long = String(repeating: "word ", count: 400)
        let lines = LRC.parse("[00:01.00]" + long + "\n[00:02.00]short")
        #expect(lines[0].text.count <= LyricsLimits.maxLineCharacters)
        #expect(lines[0].text.hasPrefix("word word"))
        #expect(lines[0].text == lines[0].text.trimmingCharacters(in: .whitespaces))
        #expect(lines[1].text == "short")
    }

    @Test func aFloodOfTimestampsOnOneLineIsBounded() {
        let body = String(repeating: "[00:01.00]", count: 100_000) + "x"
        var lines: [LyricLine] = []
        let time = ContinuousClock().measure { lines = LRC.parse(body) }
        #expect(lines.count == LyricsLimits.maxLines)
        #expect(time < .seconds(2))
    }

    @Test func clippingKeepsShortTextAndTrimsTheCut() {
        #expect(LyricsLimits.clipped("short") == "short")
        let exact = String(repeating: "a", count: LyricsLimits.maxLineCharacters)
        #expect(LyricsLimits.clipped(exact) == exact)
        let cutInSpace = String(repeating: "a", count: LyricsLimits.maxLineCharacters - 1) + " tail"
        #expect(LyricsLimits.clipped(cutInSpace) == String(repeating: "a", count: LyricsLimits.maxLineCharacters - 1))
    }

    @Test func onlyAShortLineIsLitWordByWord() {
        #expect(LyricsLimits.lightsWords(in: String(repeating: "a", count: LyricsLimits.maxWordLitCharacters)))
        #expect(!LyricsLimits.lightsWords(in: String(repeating: "a", count: LyricsLimits.maxWordLitCharacters + 1)))
        #expect(LyricsLimits.maxWordLitCharacters <= LyricsLimits.maxLineCharacters)
        // At most 20 wake-ups a second for the lit line.
        #expect(LyricsLimits.minimumWordWake >= 0.05)
    }

    // MARK: The disk cache

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("lyr-\(UUID())")
    }

    @Test func anAnswerTooBigForTheCacheIsNotKept() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = LyricsCache(directory: dir)
        let query = LRCLIBQuery(artist: "A", title: "Huge", duration: 100)
        cache.save(.plain(String(repeating: "a", count: LyricsLimits.maxCachedEntryBytes + 1)), for: query)
        #expect(cache.load(query) == nil)
        // A normal answer for another track is kept.
        let small = LRCLIBQuery(artist: "A", title: "Small", duration: 100)
        cache.save(.plain("la la"), for: small)
        #expect(cache.load(small) == .plain("la la"))
    }

    @Test func aCachedLyricFromBeforeTheLimitsIsClampedWhenItLoads() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = LyricsCache(directory: dir)
        let query = LRCLIBQuery(artist: "A", title: "Long", duration: 100)
        let many = (0..<(LyricsLimits.maxLines + 100)).map { LyricLine(time: Double($0), text: "x") }
        cache.save(.synced(many), for: query)
        guard case .synced(let loaded)? = cache.load(query) else { Issue.record("expected a synced lyric"); return }
        #expect(loaded.count == LyricsLimits.maxLines)
    }

    // MARK: Title length

    @Test func aTitleOverTheLimitIsNeverCleanedUp() {
        let long = String(repeating: "a", count: LyricsLimits.maxTitleCharacters) + " (Remastered)"
        #expect(LyricsTitle.stripped(long) == long)
        let limit = String(repeating: "a", count: LyricsLimits.maxTitleCharacters - 13) + " (Remastered)"
        #expect(LyricsTitle.stripped(limit) == String(repeating: "a", count: LyricsLimits.maxTitleCharacters - 13))
    }
}
