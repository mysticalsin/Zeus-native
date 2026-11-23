import Testing
import ZeusCore
@testable import Zeus

@Suite("Lyric timing wiring")
struct LyricTimingWiringTests {
    @Test func theLyricViewUsesStampedWordsWhenTheLineHasThem() {
        let line = LyricLine(time: 4, text: "red blue", wordStamps: [
            LyricWord(text: "red ", start: 4, end: 4.5),
            LyricWord(text: "blue", start: 4.5, end: 4.5),
        ])
        let words = LyricViewTiming.words(in: line, lineEnd: 6)
        #expect(words.map(\.start) == [4, 4.5])
        #expect(words.last?.end == 6)
        let plain = LyricViewTiming.words(in: LyricLine(time: 0, text: "red blue"), lineEnd: 2)
        #expect(plain.map(\.start) == [0, 1])
        #expect(plain.last?.end == 2)
    }
}
