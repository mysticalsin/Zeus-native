import Foundation
import Testing
@testable import ZeusCore

/// Phase 5 ElevenLabs timestamps (`docs/POINTING-ASSISTANT-PLAN.md`).
/// Word marks come from the alignment arrays. Audio is ignored.
/// A bad duration or a non-finite time yields no marks.
@Suite("Explanation ElevenLabs alignment")
struct ExplanationElevenLabsAlignmentTests {
    private typealias Alignment = ExplanationElevenLabsAlignment

    private func object(_ json: String) -> Data { Data(json.utf8) }

    private func fragment(_ characters: [String], _ starts: [Double], _ ends: [Double]) -> Alignment.Fragment {
        Alignment.Fragment(characters: characters, starts: starts, ends: ends)
    }

    private func mark(_ marks: [Alignment.Mark], _ index: Int) -> Alignment.Mark? {
        marks.indices.contains(index) ? marks[index] : nil
    }

    private func expectOrdered(_ marks: [Alignment.Mark], duration: Double) {
        #expect(marks.count <= Alignment.maximumMarks)
        var previousIndex = -1
        var previousEnd = 0.0
        for mark in marks {
            #expect(mark.wordIndex == previousIndex + 1)
            #expect(mark.wordIndex <= 4096)
            #expect(mark.start.isFinite && mark.end.isFinite)
            #expect(mark.start >= previousEnd)
            #expect(mark.end >= mark.start)
            #expect(mark.end <= duration)
            previousIndex = mark.wordIndex
            previousEnd = mark.end
        }
    }

    @Test func theReaderTakesAlignmentFromTheObjectAndIgnoresAudio() {
        let good = """
        {"audio_base64":"!!","alignment":{"characters":["H","i"],"character_start_times_seconds":[0,0.5],\
        "character_end_times_seconds":[0.5,1]},"normalized_alignment":{"characters":["Z"],\
        "character_start_times_seconds":[0],"character_end_times_seconds":[0.2]}}
        """
        let read = Alignment.fragment(from: object(good))
        #expect(read?.characters == ["H", "i"])
        #expect(read?.starts == [0, 0.5])
        #expect(read?.ends == [0.5, 1])
        let marks = Alignment.marks(from: [object(good)], duration: 1)
        #expect(marks.count == 1)
        #expect(mark(marks, 0)?.wordIndex == 0 && mark(marks, 0)?.start == 0 && mark(marks, 0)?.end == 1)
        expectOrdered(marks, duration: 1)

        let integers = """
        {"alignment":{"characters":["A"],"character_start_times_seconds":[0],"character_end_times_seconds":[1]}}
        """
        #expect(Alignment.fragment(from: object(integers))?.ends == [1])

        let empty = """
        {"alignment":{"characters":[],"character_start_times_seconds":[],"character_end_times_seconds":[]}}
        """
        #expect(Alignment.fragment(from: object(empty)) == fragment([], [], []))
        #expect(Alignment.marks(from: [object(empty)], duration: 1).isEmpty)

        let refused = [
            "",
            "not-json",
            "[]",
            "{}",
            "{\"audio_base64\":\"AAEC\"}",
            "{\"alignment\":null}",
            "{\"normalized_alignment\":{\"characters\":[\"A\"],\"character_start_times_seconds\":[0],\"character_end_times_seconds\":[1]}}",
            "{\"alignment\":{\"characters\":[\"A\"],\"character_start_times_seconds\":[0],\"character_end_times_seconds\":[1,2]}}",
            "{\"alignment\":{\"characters\":[\"A\"],\"character_start_times_seconds\":[0]}}",
            "data: {\"alignment\":{\"characters\":[\"A\"],\"character_start_times_seconds\":[0],\"character_end_times_seconds\":[1]}}",
        ]
        for sample in refused {
            #expect(Alignment.fragment(from: object(sample)) == nil)
            #expect(Alignment.marks(from: [object(sample)], duration: 1).isEmpty)
        }
        let kept = Alignment.marks(from: [object(refused[3]), object(good), object(refused[6])], duration: 1)
        #expect(kept.count == 1 && mark(kept, 0)?.end == 1)
        expectOrdered(kept, duration: 1)
    }

    @Test func wordMarksFollowTheCharacterTimesAlreadyUsedForPointingSpeech() {
        let text = "Hi there"
        let characters = text.map(String.init)
        let starts = (0..<characters.count).map { Double($0) * 0.1 }
        let ends = starts.map { $0 + 0.1 }
        let marks = Alignment.marks(from: [fragment(characters, starts, ends)], duration: 1)
        #expect(marks.count == 2)
        #expect(mark(marks, 0)?.wordIndex == 0 && mark(marks, 0)?.start == 0 && abs((mark(marks, 0)?.end ?? -1) - 0.2) < 1e-9)
        #expect(mark(marks, 1)?.wordIndex == 1 && abs((mark(marks, 1)?.start ?? -1) - 0.3) < 1e-9 && abs((mark(marks, 1)?.end ?? -1) - 0.8) < 1e-9)
        expectOrdered(marks, duration: 1)
        #expect(Alignment.marks(from: [Alignment.Fragment](), duration: 1).isEmpty)
    }

    @Test func invalidTimesAndABadDurationYieldNoMarks() {
        let word = fragment(["A"], [0], [1])
        let kept = Alignment.marks(from: [word], duration: 1)
        #expect(kept.count == 1 && mark(kept, 0)?.start == 0 && mark(kept, 0)?.end == 1)
        for duration in [0.0, -1, Double.nan, Double.infinity, -Double.infinity] {
            #expect(Alignment.marks(from: [word], duration: duration).isEmpty)
        }
        #expect(Alignment.marks(from: [fragment(["A"], [0, 1], [1])], duration: 1).isEmpty)
        #expect(Alignment.marks(from: [fragment(["A"], [Double.nan], [1])], duration: 1).isEmpty)
        #expect(Alignment.marks(from: [word, fragment(["B"], [Double.infinity], [1])], duration: 2).isEmpty)
        #expect(Alignment.marks(from: [fragment(["A"], [0], [Double.nan])], duration: 1).isEmpty)
    }

    @Test func marksAreClampedInsideTheDurationAndDoNotOverlap() {
        let clipped = Alignment.marks(from: [fragment(["a", " ", "b"], [0, 0.4, 0.9], [0.4, 0.9, 2])], duration: 1)
        #expect(clipped.count == 2)
        #expect(mark(clipped, 0)?.start == 0 && mark(clipped, 0)?.end == 0.4)
        #expect(mark(clipped, 1)?.start == 0.9 && mark(clipped, 1)?.end == 1)
        expectOrdered(clipped, duration: 1)

        let negative = Alignment.marks(from: [fragment(["a"], [-1], [-0.5])], duration: 1)
        #expect(negative.count == 1 && mark(negative, 0)?.start == 0 && mark(negative, 0)?.end == 0)

        let past = Alignment.marks(from: [fragment(["z"], [5], [6])], duration: 1)
        #expect(past.count == 1 && mark(past, 0)?.start == 1 && mark(past, 0)?.end == 1)
        expectOrdered(past, duration: 1)
    }

    @Test func aLaterFragmentContinuesAndARestartIsClampedRatherThanShifted() {
        let first = fragment(["H", "i"], [0, 0.25], [0.25, 0.5])
        let continued = fragment([" ", "t"], [0.5, 0.75], [0.75, 1])
        let forward = Alignment.marks(from: [first, continued], duration: 1)
        #expect(forward.count == 2)
        #expect(mark(forward, 0)?.start == 0 && mark(forward, 0)?.end == 0.5)
        #expect(mark(forward, 1)?.wordIndex == 1 && mark(forward, 1)?.start == 0.75 && mark(forward, 1)?.end == 1)
        expectOrdered(forward, duration: 1)

        let restarted = fragment([" ", "t"], [0, 0.1], [0.1, 0.4])
        let clamped = Alignment.marks(from: [first, restarted], duration: 1)
        #expect(clamped.count == 2)
        #expect(mark(clamped, 1)?.start == 0.5 && mark(clamped, 1)?.end == 0.5)
        expectOrdered(clamped, duration: 1)

        let skipped = """
        {"alignment":{"characters":["x"],"character_start_times_seconds":[0.2],"character_end_times_seconds":[0.3,0.4]}}
        """
        let head = """
        {"alignment":{"characters":["H","i"],"character_start_times_seconds":[0,0.25],"character_end_times_seconds":[0.25,0.5]}}
        """
        let tail = """
        {"alignment":{"characters":[" ","t"],"character_start_times_seconds":[0.5,0.75],"character_end_times_seconds":[0.75,1]}}
        """
        let joined = Alignment.marks(from: [object(head), object(skipped), object(tail)], duration: 1)
        #expect(joined.count == 2 && mark(joined, 1)?.start == 0.75 && mark(joined, 1)?.end == 1)
    }

    @Test func namedBreaksSplitWordsAndAZeroWidthSpaceStaysInsideTheWord() {
        let joined = Alignment.marks(from: [fragment(["H", "\u{200B}", "i"], [0, 0.2, 0.4], [0.2, 0.4, 0.6])], duration: 1)
        #expect(joined.count == 1)
        #expect(mark(joined, 0)?.start == 0 && mark(joined, 0)?.end == 0.6)

        let zwnj = Alignment.marks(from: [fragment(["H", "\u{200C}", "i"], [0, 0.2, 0.4], [0.2, 0.4, 0.6])], duration: 1)
        #expect(zwnj.count == 1 && mark(zwnj, 0)?.end == 0.6)

        let alone = Alignment.marks(from: [fragment([" ", "\u{200B}", " "], [0, 0.2, 0.4], [0.2, 0.4, 0.6])], duration: 1)
        #expect(alone.count == 1 && mark(alone, 0)?.start == 0.2 && mark(alone, 0)?.end == 0.4)

        let breaks = [" ", "\n", "\t", "\u{00A0}", "\u{3000}", "\u{2028}", "\u{000B}", ""]
        for token in breaks {
            let marks = Alignment.marks(from: [fragment(["H", token, "i"], [0, 0.25, 0.5], [0.25, 0.5, 0.75])], duration: 1)
            #expect(marks.count == 2)
            #expect(mark(marks, 0)?.end == 0.25 && mark(marks, 1)?.start == 0.5 && mark(marks, 1)?.end == 0.75)
            expectOrdered(marks, duration: 1)
        }
        let spaces = Alignment.marks(from: [fragment([" ", "H", " ", " ", "i", " "], [0, 0.1, 0.2, 0.3, 0.4, 0.5], [0.1, 0.2, 0.3, 0.4, 0.5, 0.6])], duration: 1)
        #expect(spaces.count == 2 && mark(spaces, 0)?.start == 0.1 && mark(spaces, 1)?.end == 0.5)
    }

    @Test func theReaderStopsAtTheAlignmentBudget() {
        #expect(Alignment.maximumMarks == 4096)
        var characters: [String] = []
        var starts: [Double] = []
        var ends: [Double] = []
        for index in 0..<4097 {
            if index > 0 {
                let gap = Double(index) * 2 - 1
                characters.append(" ")
                starts.append(gap)
                ends.append(gap)
            }
            let start = Double(index) * 2
            characters.append("a")
            starts.append(start)
            ends.append(start + 1)
        }
        let duration = 20_000.0
        let marks = Alignment.marks(from: [fragment(characters, starts, ends)], duration: duration)
        #expect(marks.count == 4096)
        #expect(marks.first?.wordIndex == 0 && marks.first?.start == 0 && marks.first?.end == 1)
        #expect(marks.last?.wordIndex == 4095)
        #expect(marks.last?.start == 8190 && marks.last?.end == 8191)
        #expect(marks.contains { $0.end == 8193 } == false)
        expectOrdered(marks, duration: duration)
    }
}
