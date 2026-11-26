import Foundation
import Testing
@testable import ZeusCore

@Suite("System speech marker alignment")
struct SystemSpeechMarkerAlignmentTests {
    private func word(_ text: String, token: String, time: Double) -> SystemSpeechMarkerFact {
        let range = utf16Range(of: token, in: text)!
        return SystemSpeechMarkerFact(kind: .word, utf16Location: range.location, utf16Length: range.length, time: time)
    }

    @Test func measuredWordTimesStayOnThoseWords() throws {
        let text = "show the motor"
        let marks = SystemSpeechMarkerAlignment.wordMarks(
            text: text,
            markers: [word(text, token: "show", time: 0), word(text, token: "motor", time: 0.4)],
            duration: 1
        )
        #expect(marks == [
            ExplanationAlignmentMark(wordIndex: 0, start: 0, end: 0.4),
            ExplanationAlignmentMark(wordIndex: 1, start: 0.4, end: 1),
        ])
    }

    @Test func aWordWithNoMarkerIsAbsent() throws {
        let text = "alpha beta gamma"
        let marks = SystemSpeechMarkerAlignment.wordMarks(
            text: text,
            markers: [word(text, token: "beta", time: 0.25)],
            duration: 1
        )
        #expect(marks == [ExplanationAlignmentMark(wordIndex: 0, start: 0.25, end: 1)])
    }

    @Test func sentenceAndPhonemeFactsAreIgnored() throws {
        let text = "alpha"
        let range = try #require(utf16Range(of: "alpha", in: text))
        let marks = SystemSpeechMarkerAlignment.wordMarks(
            text: text,
            markers: [
                SystemSpeechMarkerFact(kind: .sentence, utf16Location: range.location, utf16Length: range.length, time: 0.1),
                SystemSpeechMarkerFact(kind: .phoneme, utf16Location: range.location, utf16Length: range.length, time: 0.2),
            ],
            duration: 1
        )
        #expect(marks.isEmpty)
    }

    @Test func aRangeThatIsNotOneWholeWordIsDropped() throws {
        let text = "Hello, world"
        let marks = SystemSpeechMarkerAlignment.wordMarks(
            text: text,
            markers: [
                SystemSpeechMarkerFact(kind: .word, utf16Location: 0, utf16Length: 5, time: 0.1),
                word(text, token: "world", time: 0.5),
            ],
            duration: 1
        )
        #expect(marks == [ExplanationAlignmentMark(wordIndex: 0, start: 0.5, end: 1)])
    }

    @Test func anExactTokenKeepsItsComma() throws {
        let text = "Hello, world"
        let marks = SystemSpeechMarkerAlignment.wordMarks(
            text: text,
            markers: [word(text, token: "Hello,", time: 0.2), word(text, token: "world", time: 0.6)],
            duration: 1
        )
        #expect(marks.map(\.start) == [0.2, 0.6])
        #expect(marks.map(\.wordIndex) == [0, 1])
    }

    @Test func aNonFiniteOrOutOfRangeTimeIsDropped() throws {
        let text = "one two"
        let marks = SystemSpeechMarkerAlignment.wordMarks(
            text: text,
            markers: [
                word(text, token: "one", time: .nan),
                word(text, token: "two", time: 1.1),
            ],
            duration: 1
        )
        #expect(marks.isEmpty)
    }

    @Test func aBadDurationYieldsNoMarks() throws {
        let text = "one"
        #expect(SystemSpeechMarkerAlignment.wordMarks(text: text, markers: [word(text, token: "one", time: 0)], duration: 0).isEmpty)
        #expect(SystemSpeechMarkerAlignment.wordMarks(text: text, markers: [word(text, token: "one", time: 0)], duration: .infinity).isEmpty)
        #expect(SystemSpeechMarkerAlignment.wordMarks(text: "", markers: [], duration: 1).isEmpty)
    }

    @Test func theEarlierDuplicateTimeWins() throws {
        let text = "one two"
        let first = word(text, token: "one", time: 0.2)
        var later = first
        later.time = 0.8
        let marks = SystemSpeechMarkerAlignment.wordMarks(
            text: text,
            markers: [later, first, word(text, token: "two", time: 0.9)],
            duration: 1
        )
        #expect(marks.first?.start == 0.2)
    }

    @Test func markersComeOutInWordOrderAndDoNotOverlap() throws {
        let text = "a b"
        let marks = SystemSpeechMarkerAlignment.wordMarks(
            text: text,
            markers: [word(text, token: "b", time: 0.4), word(text, token: "a", time: 0.5)],
            duration: 1
        )
        #expect(marks == [
            ExplanationAlignmentMark(wordIndex: 0, start: 0.5, end: 0.5),
            ExplanationAlignmentMark(wordIndex: 1, start: 0.5, end: 1),
        ])
    }

    @Test func anEmojiWordNeedsItsWholeScalar() throws {
        let text = "a 👍 b"
        let whole = try #require(utf16Range(of: "👍", in: text))
        #expect(whole.length == 2)
        let short = SystemSpeechMarkerAlignment.wordMarks(
            text: text,
            markers: [SystemSpeechMarkerFact(kind: .word, utf16Location: whole.location, utf16Length: 1, time: 0.2)],
            duration: 1
        )
        let full = SystemSpeechMarkerAlignment.wordMarks(
            text: text,
            markers: [SystemSpeechMarkerFact(kind: .word, utf16Location: whole.location, utf16Length: whole.length, time: 0.2)],
            duration: 1
        )
        #expect(short.isEmpty)
        #expect(full == [ExplanationAlignmentMark(wordIndex: 0, start: 0.2, end: 1)])
    }

    @Test func theMarkCapDropsTheRest() {
        let count = SystemSpeechMarkerAlignment.maxMarks + 1
        let text = Array(repeating: "a", count: count).joined(separator: " ")
        let markers = (0..<count).map { index in
            SystemSpeechMarkerFact(kind: .word, utf16Location: index * 2, utf16Length: 1, time: Double(index) * 0.0001)
        }
        let marks = SystemSpeechMarkerAlignment.wordMarks(text: text, markers: markers, duration: 10)
        #expect(marks.count == SystemSpeechMarkerAlignment.maxMarks)
        #expect(marks.last?.wordIndex == SystemSpeechMarkerAlignment.maxMarks - 1)
        #expect(marks.last?.start == Double(SystemSpeechMarkerAlignment.maxMarks - 1) * 0.0001)
        #expect(marks.last?.end == 10)
    }

    @Test func tooManyMarkersOrTooMuchTextYieldsNothing() {
        let text = "a"
        let marker = SystemSpeechMarkerFact(kind: .word, utf16Location: 0, utf16Length: 1, time: 0.1)
        let crowded = Array(repeating: marker, count: SystemSpeechMarkerAlignment.maxMarkers + 1)
        #expect(SystemSpeechMarkerAlignment.wordMarks(text: text, markers: crowded, duration: 1).isEmpty)
        let huge = String(repeating: "b", count: SystemSpeechMarkerAlignment.maxTextBytes + 1)
        #expect(SystemSpeechMarkerAlignment.wordMarks(text: huge, markers: [marker], duration: 1).isEmpty)
    }
}

private struct UTF16Range {
    var location: Int
    var length: Int
}

private func utf16Range(of token: String, in text: String) -> UTF16Range? {
    let haystack = Array(text.utf16)
    let needle = Array(token.utf16)
    guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
    var index = 0
    while index + needle.count <= haystack.count {
        if Array(haystack[index..<(index + needle.count)]) == needle {
            let before = index == 0 || haystack[index - 1] == 0x20
            let after = index + needle.count
            if before, after == haystack.count || haystack[after] == 0x20 {
                return UTF16Range(location: index, length: needle.count)
            }
        }
        index += 1
    }
    return nil
}
