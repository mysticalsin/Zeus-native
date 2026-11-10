import Testing
@testable import ZeusCore

/// Item 5, QA7: `AckLines.clamp` is the safety net against unbounded spliced text (a long app,
/// playlist or to-do name) blowing a short ack past the persona's one-clause, ≤10-word rule.
@Suite("Ack line clamp")
struct AckLinesTests {
    @Test func passesShortTextThroughUnchanged() {
        #expect(AckLines.clamp("Opening Safari.") == "Opening Safari.")
    }

    @Test func passesNilThrough() {
        #expect(AckLines.clamp(nil) == nil)
    }

    @Test func truncatesAtAWordBoundaryWithASingleTrailingPeriod() {
        let longApp = "Visual Studio Code Insiders Enterprise Ultra Pro Max Edition Deluxe"
        let clamped = AckLines.clamp("Opening \(longApp).", words: 10)
        #expect(clamped != nil)
        #expect(clamped!.split(separator: " ").count == 10)
        #expect(clamped!.hasSuffix("."))
        #expect(clamped!.filter { $0 == "." }.count == 1)
    }

    @Test func neverLeavesDanglingPunctuationFromTheCut() {
        // The 10th word itself carries a comma in the source text; clamp must replace it, not double up.
        let text = (1...12).map { "word\($0)," }.joined(separator: " ")
        let clamped = AckLines.clamp(text, words: 10)!
        #expect(!clamped.hasSuffix(",."))
        #expect(!clamped.contains(",,"))
        #expect(clamped.hasSuffix("."))
        #expect(clamped.filter { $0 == "." }.count == 1)
    }

    @Test func exactlyAtTheLimitIsUntouched() {
        let text = (1...10).map { "word\($0)" }.joined(separator: " ")
        #expect(AckLines.clamp(text, words: 10) == text)
    }

    @Test func oneWordOverTheLimitStillGetsClamped() {
        let text = (1...11).map { "word\($0)" }.joined(separator: " ")
        let clamped = AckLines.clamp(text, words: 10)!
        #expect(clamped.split(separator: " ").count == 10)
        #expect(!clamped.contains("word11"))
    }

    @Test func neutralAndPersonaAckLinesStayWithinTenWordsEvenWithALongName() {
        let longName = "The Quarterly Financial Planning And Strategy Review Document Final Version Two"
        for bank in [AckLines.neutral, AckLines.persona] {
            for ack in [FastAck.opening(longName), .searchingSpotify(longName), .added([longName])] {
                guard let line = bank.line(ack) else { continue }
                #expect(line.split(separator: " ").count <= 10, "\(line)")
            }
        }
    }
}
