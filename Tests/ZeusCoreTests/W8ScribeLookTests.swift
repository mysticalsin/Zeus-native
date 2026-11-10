import Foundation
import Testing
import ZeusCore

@Suite("Scribe look: speaker stats and ticker text")
struct W8ScribeLookTests {
    private let session = ScribeSessionID()

    private func segment(_ id: String, _ speaker: ScribeSpeaker, _ start: TimeInterval, _ end: TimeInterval, _ text: String = "words") -> ScribeTranscriptSegment {
        ScribeTranscriptSegment(id: id, session: session, speaker: speaker, start: start, end: end, text: text, isFinal: true)
    }

    @Test func talkTimeSharesAndCountsPerSpeaker() {
        let stats = ScribeSpeakerStats(segments: [
            segment("a", .you, 0, 6),
            segment("b", .participant("Speaker 1"), 6, 8),
            segment("c", .you, 8, 10),
        ])
        #expect(stats.speakers.count == 2)
        #expect(stats.speakers[0].speaker == .you)
        #expect(stats.speakers[0].talkSeconds == 8)
        #expect(stats.speakers[0].segmentCount == 2)
        #expect(abs(stats.speakers[0].share - 0.8) < 0.0001)
        #expect(stats.speakers[1].talkSeconds == 2)
        #expect(abs(stats.speakers[1].share - 0.2) < 0.0001)
        #expect(stats.totalTalkSeconds == 10)
    }

    @Test func firstAppearanceOrderIsKept() {
        let stats = ScribeSpeakerStats(segments: [
            segment("a", .participant("Speaker 2"), 0, 1),
            segment("b", .you, 1, 5),
            segment("c", .participant("Speaker 2"), 5, 6),
        ])
        #expect(stats.speakers.map(\.speaker) == [.participant("Speaker 2"), .you])
    }

    @Test func emptyTextIsIgnored() {
        let stats = ScribeSpeakerStats(segments: [
            segment("a", .you, 0, 4, "  \n"),
            segment("b", .participant("Speaker 1"), 4, 6, "hello"),
        ])
        #expect(stats.speakers.count == 1)
        #expect(stats.speakers[0].speaker == .participant("Speaker 1"))
        #expect(stats.speakers[0].share == 1)
    }

    @Test func negativeLengthCountsAsZero() {
        let stats = ScribeSpeakerStats(segments: [
            segment("a", .you, 5, 2),
            segment("b", .participant("Speaker 1"), 5, 9),
        ])
        #expect(stats.speakers[0].talkSeconds == 0)
        #expect(stats.speakers[0].share == 0)
        #expect(stats.speakers[1].share == 1)
    }

    @Test func zeroLengthSegmentsShareByCount() {
        let stats = ScribeSpeakerStats(segments: [
            segment("a", .you, 1, 1),
            segment("b", .you, 2, 2),
            segment("c", .participant("Speaker 1"), 3, 3),
        ])
        #expect(abs(stats.speakers[0].share - 2.0 / 3.0) < 0.0001)
        #expect(abs(stats.speakers[1].share - 1.0 / 3.0) < 0.0001)
    }

    @Test func emptyTranscriptHasNoSpeakers() {
        let stats = ScribeSpeakerStats(segments: [])
        #expect(stats.speakers.isEmpty)
        #expect(!stats.isWorthShowing)
    }

    @Test func lonelySpeakerWithNoTalkTimeIsHidden() {
        let silent = ScribeSpeakerStats(segments: [segment("a", .you, 3, 3)])
        #expect(!silent.isWorthShowing)
        let talking = ScribeSpeakerStats(segments: [segment("a", .you, 0, 3)])
        #expect(talking.isWorthShowing)
        let two = ScribeSpeakerStats(segments: [segment("a", .you, 3, 3), segment("b", .participant("Speaker 1"), 4, 4)])
        #expect(two.isWorthShowing)
    }

    @Test func talkTimeFormatsAsMinutesAndSeconds() {
        #expect(ScribeSpeakerStats.format(0) == "0:00")
        #expect(ScribeSpeakerStats.format(5) == "0:05")
        #expect(ScribeSpeakerStats.format(65.4) == "1:05")
        #expect(ScribeSpeakerStats.format(3725) == "62:05")
        #expect(ScribeSpeakerStats.format(-3) == "0:00")
        #expect(ScribeSpeakerStats.format(.nan) == "0:00")
    }

    @Test func tickerTailKeepsTheNewestWords() {
        #expect(ScribeTickerText.tail("one two three four five", words: 3) == "three four five")
        #expect(ScribeTickerText.tail("one  two", words: 5) == "one two")
        #expect(ScribeTickerText.tail("one two", words: 0) == "")
        #expect(ScribeTickerText.tail("", words: 3) == "")
    }

    @Test func placeholderIsNotWords() {
        #expect(!ScribeTickerText.hasWords("…"))
        #expect(!ScribeTickerText.hasWords("  "))
        #expect(ScribeTickerText.hasWords("hi"))
    }
}
