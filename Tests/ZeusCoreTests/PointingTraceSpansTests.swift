import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing trace spans")
struct PointingTraceSpansTests {
    @Test func theLineHasOffsetsInMillisecondsAndDashesForMissingMarks() {
        var spans = PointingTraceSpans()
        spans.mark(.keyDown, at: 100.0)
        spans.mark(.firstMic, at: 100.041)
        spans.mark(.requestSent, at: 101.2)
        let line = spans.line(outcome: .completed)
        #expect(line.hasPrefix("[ZEUS] pointing-trace outcome=completed key_down=0 first_mic=41 transcript_final=-"))
        #expect(line.contains("request_sent=1200"))
        #expect(line.hasSuffix("cancel_complete=-"))
    }

    @Test func everyMarkAppearsOnce() {
        let line = PointingTraceSpans().line(outcome: .failed)
        for mark in PointingTraceSpans.Mark.allCases {
            #expect(line.components(separatedBy: "\(mark.rawValue)=").count == 2, "\(mark)")
        }
    }

    @Test func theFirstWriteOfAMarkWins() {
        var spans = PointingTraceSpans()
        spans.mark(.keyDown, at: 1)
        spans.mark(.firstAudio, at: 2)
        spans.mark(.firstAudio, at: 9)
        #expect(spans.line(outcome: .completed).contains("first_audio=1000"))
    }

    @Test func nonFiniteTimesAreIgnoredAndEarlierThanKeyDownClampsToZero() {
        var spans = PointingTraceSpans()
        spans.mark(.keyDown, at: 10)
        spans.mark(.firstMic, at: .nan)
        spans.mark(.firstVisual, at: 9)
        let line = spans.line(outcome: .cancelled)
        #expect(line.contains("first_mic=-"))
        #expect(line.contains("first_visual=0"))
    }

    @Test func theLineCarriesNoFreeTextOnlyKnownTokens() {
        var spans = PointingTraceSpans()
        spans.mark(.keyDown, at: 0)
        let allowed = Set(PointingTraceSpans.Mark.allCases.map(\.rawValue) + ["outcome"])
        for field in spans.line(outcome: .interrupted).split(separator: " ").dropFirst(2) {
            #expect(allowed.contains(String(field.split(separator: "=")[0])))
        }
    }

    @Test func aNeverWrittenTraceIsEmpty() {
        #expect(PointingTraceSpans().isEmpty)
    }

    @Test func pointerFillColourIgnoresTheDefaultWhiteAndBadValues() {
        #expect(PointerFillColor.parse(nil) == nil)
        #expect(PointerFillColor.parse(["red": 1, "green": 1, "blue": 1]) == nil)
        #expect(PointerFillColor.parse(["red": 0.2, "green": 0.4]) == nil)
        #expect(PointerFillColor.parse(["red": 2, "green": 0, "blue": 0]) == nil)
        let fill = PointerFillColor.parse(["red": 0.9, "green": 0.2, "blue": 0.1])
        #expect(fill?.red == 0.9 && fill?.blue == 0.1)
    }
}
