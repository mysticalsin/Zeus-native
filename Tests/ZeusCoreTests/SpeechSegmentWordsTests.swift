import Foundation
import Testing
@testable import ZeusCore

@Suite("Speech segment words")
struct SpeechSegmentWordsTests {
    @Test func aMeasuredStartStaysOnThatWord() {
        let words = SpeechSegmentWords.words(from: [
            SpeechSegmentFact(text: "this", start: 1.5),
        ])
        #expect(words == [SpeechSegmentWord(text: "this", start: 1.5)])
    }

    @Test func everyWordInASegmentSharesItsStart() {
        let words = SpeechSegmentWords.words(from: [
            SpeechSegmentFact(text: "this\tbutton here", start: 1.5),
        ])
        #expect(words == [
            SpeechSegmentWord(text: "this", start: 1.5),
            SpeechSegmentWord(text: "button", start: 1.5),
            SpeechSegmentWord(text: "here", start: 1.5),
        ])
    }

    @Test func aStartOfZeroIsTheBeginning() {
        let words = SpeechSegmentWords.words(from: [
            SpeechSegmentFact(text: "go now", start: 0),
        ])
        #expect(words == [
            SpeechSegmentWord(text: "go", start: 0),
            SpeechSegmentWord(text: "now", start: 0),
        ])
    }

    @Test func aMissingOrUnusableTimeStaysUnset() {
        let words = SpeechSegmentWords.words(from: [
            SpeechSegmentFact(text: "nope", start: nil),
            SpeechSegmentFact(text: "neg", start: -0.01),
            SpeechSegmentFact(text: "bad", start: .nan),
            SpeechSegmentFact(text: "inf", start: .infinity),
            SpeechSegmentFact(text: "ok", start: 1.25),
        ])
        #expect(words.map(\.text) == ["nope", "neg", "bad", "inf", "ok"])
        #expect(words.map(\.start) == [nil, nil, nil, nil, 1.25])
    }

    @Test func anEarlierSegmentDoesNotTakeALaterTime() {
        let words = SpeechSegmentWords.words(from: [
            SpeechSegmentFact(text: "what is", start: nil),
            SpeechSegmentFact(text: "this", start: 2),
        ])
        #expect(words == [
            SpeechSegmentWord(text: "what", start: nil),
            SpeechSegmentWord(text: "is", start: nil),
            SpeechSegmentWord(text: "this", start: 2),
        ])
    }

    @Test func blankSegmentsAddNoWords() {
        let words = SpeechSegmentWords.words(from: [
            SpeechSegmentFact(text: " \n\t", start: 4),
            SpeechSegmentFact(text: "", start: 4),
            SpeechSegmentFact(text: "here", start: 4),
        ])
        #expect(words == [SpeechSegmentWord(text: "here", start: 4)])
    }

    @Test func punctuationStaysOnTheToken() {
        let words = SpeechSegmentWords.words(from: [
            SpeechSegmentFact(text: "This, ça", start: 0.2),
            SpeechSegmentFact(text: "this\u{200B}that", start: 0.8),
        ])
        #expect(words == [
            SpeechSegmentWord(text: "This,", start: 0.2),
            SpeechSegmentWord(text: "ça", start: 0.2),
            SpeechSegmentWord(text: "this\u{200B}that", start: 0.8),
        ])
    }

    @Test func aSegmentPastTheBudgetYieldsNothing() {
        let huge = String(repeating: "a", count: SpeechSegmentWords.maxTextBytes + 1)
        #expect(SpeechSegmentWords.words(from: [SpeechSegmentFact(text: huge, start: 1)]).isEmpty)
        let exact = String(repeating: "b", count: SpeechSegmentWords.maxTextBytes)
        #expect(SpeechSegmentWords.words(from: [SpeechSegmentFact(text: exact, start: 3)]) == [
            SpeechSegmentWord(text: exact, start: 3),
        ])
        let half = String(repeating: "c", count: SpeechSegmentWords.maxTextBytes / 2 + 1)
        #expect(SpeechSegmentWords.words(from: [
            SpeechSegmentFact(text: half, start: 1),
            SpeechSegmentFact(text: half, start: 1),
        ]).isEmpty)
        let tooMany = Array(repeating: SpeechSegmentFact(text: "a", start: 2), count: SpeechSegmentWords.maxSegments + 1)
        #expect(SpeechSegmentWords.words(from: tooMany).isEmpty)
        let atLimit = Array(repeating: SpeechSegmentFact(text: "a", start: 2), count: SpeechSegmentWords.maxSegments)
        let kept = SpeechSegmentWords.words(from: atLimit)
        #expect(kept.count == SpeechSegmentWords.maxWords)
        #expect(kept.allSatisfy { $0.text == "a" && $0.start == 2 })
    }

    @Test func wordsStopAtTheCap() {
        let text = Array(repeating: "a", count: SpeechSegmentWords.maxWords + 1).joined(separator: " ")
        let words = SpeechSegmentWords.words(from: [SpeechSegmentFact(text: text, start: 5)])
        #expect(words.count == SpeechSegmentWords.maxWords)
        #expect(words.allSatisfy { $0 == SpeechSegmentWord(text: "a", start: 5) })
    }
}
