import Foundation
import Testing
@testable import ZeusCore

@Suite("Lyrics matching box")
struct LyricsMatchingBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(LyricsMatchingBox.blankScalars.contains(" "))
        #expect(LyricsMatchingBox.blankScalars.contains("\t"))
        #expect(LyricsMatchingBox.blankScalars.contains("\n"))
        #expect(LyricsMatchingBox.blankScalars.contains("\u{000B}"))
        #expect(LyricsMatchingBox.blankScalars.contains("\u{000C}"))
        #expect(LyricsMatchingBox.blankScalars.contains("\r"))
        #expect(LyricsMatchingBox.blankScalars.contains("\u{0085}"))
        #expect(LyricsMatchingBox.blankScalars.contains("\u{00A0}"))
        #expect(LyricsMatchingBox.blankScalars.contains("\u{1680}"))
        #expect(LyricsMatchingBox.blankScalars.contains("\u{2000}"))
        #expect(LyricsMatchingBox.blankScalars.contains("\u{200A}"))
        #expect(LyricsMatchingBox.blankScalars.contains("\u{2028}"))
        #expect(LyricsMatchingBox.blankScalars.contains("\u{2029}"))
        #expect(LyricsMatchingBox.blankScalars.contains("\u{202F}"))
        #expect(LyricsMatchingBox.blankScalars.contains("\u{205F}"))
        #expect(LyricsMatchingBox.blankScalars.contains("\u{3000}"))
        #expect(!LyricsMatchingBox.blankScalars.contains("\u{200B}"))
        #expect(LyricsMatchingBox.trimmedText("\u{200B}") == "\u{200B}")
        #expect(LyricsMatchingBox.trimmedText(" \u{200B} ") == "\u{200B}")
        #expect(LyricsMatchingBox.trimmedText(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aBodyOfOnlyNamedBlanksIsEmpty() {
        #expect(LyricsMatchingBox.trimmedText("") == "")
        #expect(LyricsMatchingBox.trimmedText(" \t\n\r") == "")
        #expect(LyricsMatchingBox.trimmedText("\u{00A0}") == "")
        #expect(LyricsMatchingBox.trimmedText("\u{1680}\u{2000}\u{2028}\u{202F}\u{205F}\u{3000}") == "")
        #expect(LyricsMatchingBox.trimmedText("\u{200B}") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysInATitleAndAnArtist() {
        #expect(LyricsTitle.stripped("Song (Remastered)") == "Song")
        #expect(LyricsTitle.stripped("\u{200B} (Remastered)") == "\u{200B}")
        #expect(LyricsTitle.stripped("\u{200B}Song (Remastered)") == "\u{200B}Song")
        #expect(LyricsTitle.primaryArtist("  Artist A , Artist B ") == "Artist A")
        #expect(LyricsTitle.primaryArtist("\u{00A0}Queen feat. David Bowie") == "Queen")
        #expect(LyricsTitle.primaryArtist("\u{200B}Queen feat. David Bowie") == "\u{200B}Queen")
        #expect(LyricsTitle.withoutFeaturedArtists("\u{200B}Queen feat. David Bowie") == "\u{200B}Queen")
        #expect(LyricsTitle.withoutFeaturedArtists("Queen & David Bowie") == "Queen & David Bowie")
    }

    @Test func aPlainLyricOfOnlyAZeroWidthSpaceStillCounts() {
        let mark = LyricsCandidate(id: 1, title: "Song", artist: "Queen", duration: 10, instrumental: false,
                                    syncedText: nil, plainText: "\u{200B}")
        #expect(mark.result == .plain("\u{200B}"))
        let blank = LyricsCandidate(id: 2, title: "Song", artist: "Queen", duration: 10, instrumental: false,
                                     syncedText: nil, plainText: "\u{00A0}")
        #expect(blank.result == .none)
        let kept = Data("[{\"id\":1,\"trackName\":\"Song\",\"artistName\":\"Queen\",\"duration\":10,\"plainLyrics\":\"\(zwsp)\"}]".utf8)
        let parsed = LRCLIBResponse.parseSearch(kept)
        #expect(parsed.count == 1)
        #expect(parsed.first?.plainText == "\u{200B}")
        #expect(parsed.first?.result == .plain("\u{200B}"))
        let dropped = Data("[{\"id\":2,\"trackName\":\"Song\",\"artistName\":\"Queen\",\"duration\":10,\"plainLyrics\":\"\(nbsp)\"}]".utf8)
        #expect(LRCLIBResponse.parseSearch(dropped).first?.plainText == nil)
    }

    @Test func aZeroWidthSpaceKeepsATitleFromMatchingADifferentOne() {
        let song = LyricsCandidate(id: 1, title: "Song", artist: "Queen", duration: 0, instrumental: false,
                                    syncedText: nil, plainText: "la")
        #expect(LyricsMatch.best([song], duration: 0, title: "\u{00A0}Song")?.id == 1)
        #expect(LyricsMatch.best([song], duration: 0, title: "\u{200B}Song") == nil)
        let marked = LyricsCandidate(id: 2, title: "\u{200B}Song", artist: "Queen", duration: 0, instrumental: false,
                                      syncedText: nil, plainText: "\u{200B}")
        #expect(LyricsMatch.best([marked], duration: 0, title: "\u{200B}Song")?.id == 2)
        #expect(marked.result == .plain("\u{200B}"))
    }
}

private let zwsp = "\u{200B}"
private let nbsp = "\u{00A0}"
