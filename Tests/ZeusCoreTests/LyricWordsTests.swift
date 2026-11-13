import Foundation
import Testing
@testable import ZeusCore

/// Word by word lyrics (plan M3): syllable units, the sung span shared among words, which word is lit,
/// when it changes next, and inline word tags kept out of the text. Pure, no clock, no network.
@Suite struct LyricWordsTests {
    // MARK: Units

    @Test func latinUnitsAreVowelGroups() {
        let table: [(String, Int)] = [
            ("hello", 2), ("the", 1), ("beautiful", 3), ("queue", 1), ("Hello,", 2),
            ("don't", 1), ("I'm", 1), ("a", 1), ("123", 1), ("Café", 2),
        ]
        for (word, expected) in table {
            #expect(LyricWordTiming.units(word) == expected, "\(word)")
        }
    }

    @Test func aWordWithLettersNeverCountsLessThanOne() {
        #expect(LyricWordTiming.units("rhythm") >= 1)
        #expect(LyricWordTiming.units("hmm") == 1)
        #expect(LyricWordTiming.units("Привет") >= 1)
    }

    @Test func punctuationAloneCountsAsNothing() {
        for text in ["!", "...", "-", "\u{201C}", "", "  ", "\u{266A}"] {
            #expect(LyricWordTiming.units(text) == 0, "\(text)")
        }
    }

    @Test func cjkCountsOnePerCharacter() {
        #expect(LyricWordTiming.units("こんにちは") == 5)   // kana
        #expect(LyricWordTiming.units("夜空") == 2)          // kanji
        #expect(LyricWordTiming.units("夜空を見上げて") == 7)
        #expect(LyricWordTiming.units("사랑해") == 3)        // hangul syllables
        #expect(LyricWordTiming.units("Hello世界") == 4)     // mixed: 2 + 2
    }

    // MARK: Words and shares

    private func word(_ text: String, _ start: Double, _ end: Double) -> LyricWord { LyricWord(text: text, start: start, end: end) }

    @Test func spanIsSharedByUnits() {
        let words = LyricWordTiming.words(in: LyricLine(time: 10, text: "Hello world"), lineEnd: 20)
        // hello 2 units, world 1 unit: span max(1.0, 3 * 0.45) = 1.35.
        #expect(words.map(\.text) == ["Hello ", "world"])
        #expect(words[0].start == 10)
        #expect(abs(words[0].end - 10.9) < 1e-9)
        #expect(words[1].start == words[0].end)
        #expect(abs(words[1].end - 11.35) < 1e-9)
    }

    @Test func sharesSumToTheSungSpan() {
        let line = LyricLine(time: 3, text: "Somewhere over the rainbow way up high")
        let words = LyricWordTiming.words(in: line, lineEnd: 60)
        let units = 3 + 2 + 1 + 2 + 1 + 1 + 1   // some-where, o-ver, the, rain-bow, way, up, high
        let span = Double(units) * 0.45
        let shares = words.map { $0.end - $0.start }
        #expect(abs(shares.reduce(0, +) - span) < 1e-9)
        #expect(words.first?.start == 3)
        #expect(abs((words.last?.end ?? 0) - (3 + span)) < 1e-9)
        for pair in zip(words, words.dropFirst()) { #expect(pair.0.end == pair.1.start) }
    }

    @Test func aLongGapIsCappedAndTheWordsFinishEarly() {
        let words = LyricWordTiming.words(in: LyricLine(time: 0, text: "Hello world"), lineEnd: 100)
        #expect(abs((words.last?.end ?? 0) - 1.35) < 1e-9)
        // After the span the last word stays the lit one for the whole gap.
        #expect(LyricWordTiming.index(words, at: 90) == 1)
    }

    @Test func aShortGapCapsTheSpanAtTheNextLine() {
        let words = LyricWordTiming.words(in: LyricLine(time: 4, text: "Hello world"), lineEnd: 4.5)
        #expect(abs((words.last?.end ?? 0) - 4.5) < 1e-9)
    }

    @Test func aOneWordLineSingsForAtLeastOneSecond() {
        let short = LyricWordTiming.words(in: LyricLine(time: 5, text: "the"), lineEnd: 30)
        #expect(short.count == 1)
        #expect(short[0].start == 5 && abs(short[0].end - 6) < 1e-9)
        let long = LyricWordTiming.words(in: LyricLine(time: 5, text: "Hallelujah"), lineEnd: 30)
        #expect(long.count == 1)
        #expect(abs(long[0].end - (5 + 4 * 0.45)) < 1e-9)   // hal-le-lu-jah
    }

    @Test func anEmptyLineHasNoWords() {
        #expect(LyricWordTiming.words(in: LyricLine(time: 1, text: ""), lineEnd: 9).isEmpty)
        #expect(LyricWordTiming.words(in: LyricLine(time: 1, text: "   "), lineEnd: 9).isEmpty)
    }

    @Test func wordTextsAddUpToTheLine() {
        for text in ["Hello world", "Hello - world!", "\u{BF}Qu\u{E9} pasa?", "  spaced   out  ", "Hello \u{4E16}\u{754C} again", "...", "No no no, no"] {
            let words = LyricWordTiming.words(in: LyricLine(time: 0, text: text), lineEnd: 30)
            #expect(words.map(\.text).joined() == text.trimmingCharacters(in: .whitespaces), "\(text)")
        }
    }

    @Test func punctuationJoinsTheWordBeforeItAndTakesNoTime() {
        let words = LyricWordTiming.words(in: LyricLine(time: 0, text: "Hello - world!"), lineEnd: 30)
        #expect(words.map(\.text) == ["Hello - ", "world!"])
        let leading = LyricWordTiming.words(in: LyricLine(time: 0, text: "\u{BF}Qu\u{E9} pasa?"), lineEnd: 30)
        #expect(leading.map(\.text) == ["\u{BF}Qu\u{E9} ", "pasa?"])
    }

    @Test func aLineOfOnlyPunctuationIsOneWord() {
        let words = LyricWordTiming.words(in: LyricLine(time: 2, text: "..."), lineEnd: 30)
        #expect(words.map(\.text) == ["..."])
        #expect(words[0].start == 2 && abs(words[0].end - 3) < 1e-9)
    }

    @Test func cjkWithoutSpacesSplitsPerCharacter() {
        let words = LyricWordTiming.words(in: LyricLine(time: 0, text: "こんにちは"), lineEnd: 30)
        #expect(words.map(\.text) == ["こ", "ん", "に", "ち", "は"])
        // Five units: span max(1.0, 2.25) = 2.25, one fifth each.
        for word in words { #expect(abs((word.end - word.start) - 0.45) < 1e-9) }
        let mixed = LyricWordTiming.words(in: LyricLine(time: 0, text: "Hello \u{4E16}\u{754C}"), lineEnd: 30)
        #expect(mixed.map(\.text) == ["Hello ", "\u{4E16}", "\u{754C}"])
    }

    @Test func aLineEndBeforeTheLineStartGivesZeroLengthWords() {
        let words = LyricWordTiming.words(in: LyricLine(time: 8, text: "Hello world"), lineEnd: 7)
        #expect(words.count == 2)
        #expect(words.allSatisfy { $0.start == 8 && $0.end == 8 })
    }

    // MARK: Which word is lit

    private let three = [LyricWord(text: "A ", start: 10, end: 11), LyricWord(text: "B ", start: 11, end: 12), LyricWord(text: "C", start: 12, end: 13)]

    @Test func indexAtAndBetweenBoundaries() {
        #expect(LyricWordTiming.index(three, at: 9.99) == nil)
        #expect(LyricWordTiming.index(three, at: 10) == 0)
        #expect(LyricWordTiming.index(three, at: 10.5) == 0)
        #expect(LyricWordTiming.index(three, at: 10.999) == 0)
        #expect(LyricWordTiming.index(three, at: 11) == 1)
        #expect(LyricWordTiming.index(three, at: 12.5) == 2)
        #expect(LyricWordTiming.index(three, at: 13) == 2)
        #expect(LyricWordTiming.index(three, at: 500) == 2)
        #expect(LyricWordTiming.index([], at: 10) == nil)
    }

    @Test func nextChangeAtAndBetweenBoundaries() {
        #expect(LyricWordTiming.nextChange(three, after: 5) == 10)
        #expect(LyricWordTiming.nextChange(three, after: 9.99) == 10)
        #expect(LyricWordTiming.nextChange(three, after: 10) == 11)
        #expect(LyricWordTiming.nextChange(three, after: 10.5) == 11)
        #expect(LyricWordTiming.nextChange(three, after: 11) == 12)
        #expect(LyricWordTiming.nextChange(three, after: 12) == nil)
        #expect(LyricWordTiming.nextChange(three, after: 12.5) == nil)
        #expect(LyricWordTiming.nextChange([], after: 0) == nil)
    }

    @Test func nextChangeIsAlwaysTheNextIndexStep() {
        let words = LyricWordTiming.words(in: LyricLine(time: 20, text: "Somewhere over the rainbow"), lineEnd: 60)
        var time = 19.0
        var seen: [Int?] = [LyricWordTiming.index(words, at: time)]
        while let next = LyricWordTiming.nextChange(words, after: time) {
            time = next
            seen.append(LyricWordTiming.index(words, at: time))
        }
        #expect(seen == [nil, 0, 1, 2, 3])
    }

    // MARK: Line end

    @Test func lineEndIsTheNextLineOrFourSecondsAfterTheLast() {
        let lines = [LyricLine(time: 1, text: "a"), LyricLine(time: 6, text: "b"), LyricLine(time: 20, text: "c")]
        #expect(lines.lineEnd(at: 0) == 6)
        #expect(lines.lineEnd(at: 1) == 20)
        #expect(lines.lineEnd(at: 2) == 24)
        #expect(lines.lineEnd(at: 2, trackEnd: 200) == 200)
    }

    // MARK: Inline word tags in a lyric file

    @Test func inlineWordTagsAreStrippedFromTheText() {
        let lines = LRC.parse("[00:12.00]<00:12.00>Hello <00:12.50>world")
        #expect(lines == [LyricLine(time: 12, text: "Hello world")])
    }

    @Test func aTrailingTagAndSeveralLinesAreHandled() {
        let lrc = """
        [ar:Someone]
        [00:01.00]<00:01.00>One <00:01.40>two <00:01.80>
        [00:05.00]<00:05.00>Three
        [00:09.00]<00:09.00>
        """
        let lines = LRC.parse(lrc)
        #expect(lines.map(\.text) == ["One two", "Three", ""])
        #expect(lines.map(\.time) == [1, 5, 9])
    }

    @Test func tagsThatAreNotTimestampsStayInTheText() {
        #expect(LRC.parse("[00:03.00]I <3 you").first?.text == "I <3 you")
        #expect(LRC.parse("[00:03.00]<i>Hello</i>").first?.text == "<i>Hello</i>")
        #expect(LRC.parse("[00:03.00]Hello <world").first?.text == "Hello <world")
    }

    @Test func plainLinesAreUnchanged() {
        #expect(LRC.parse("[00:03.00]Just words here").first?.text == "Just words here")
    }
}
