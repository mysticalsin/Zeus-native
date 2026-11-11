import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing deixis")
struct PointingDeixisTests {
    private let valid: Set<String> = ["t0", "t1", "t2"]

    @Test func recognisesPointingWordsIgnoringCaseAndPunctuation() {
        #expect(PointingDeixis.isDeictic("This,"))
        #expect(PointingDeixis.isDeictic("HERE"))
        #expect(PointingDeixis.isDeictic("ça"))
        #expect(!PointingDeixis.isDeictic("thistle"))
        #expect(!PointingDeixis.isDeictic("button"))
    }

    @Test func splitsATranscriptIntoUntimedWords() {
        let words = PointingDeixis.words(in: "what is this and that")
        #expect(words.count == 5)
        #expect(words.allSatisfy { $0.start == nil })
    }

    @Test func untimedWordsTakeEvidenceInOrder() {
        let words = PointingDeixis.words(in: "is this the same as that")
        let evidence = [PointingDeixis.Evidence(time: 2, candidateID: "t1"), .init(time: 1, candidateID: "t0")]
        let result = PointingDeixis.resolve(words: words, evidence: evidence, validIDs: valid)
        #expect(result == [.init(word: "this", candidateID: "t0"), .init(word: "that", candidateID: "t1")])
    }

    @Test func extraWordsReuseTheLastEvidence() {
        let words = PointingDeixis.words(in: "this here that")
        let result = PointingDeixis.resolve(words: words, evidence: [.init(time: 1, candidateID: "t2")], validIDs: valid)
        #expect(result.map(\.candidateID) == ["t2", "t2", "t2"])
    }

    @Test func timedWordsTakeTheNearestEvidenceInsideTheWindow() {
        let words = [PointingDeixis.Word(text: "this", start: 1.0), .init(text: "that", start: 3.0), .init(text: "here", start: 10)]
        let evidence = [PointingDeixis.Evidence(time: 0.9, candidateID: "t0"), .init(time: 3.1, candidateID: "t1")]
        let result = PointingDeixis.resolve(words: words, evidence: evidence, validIDs: valid)
        #expect(result.map(\.candidateID) == ["t0", "t1", nil])
    }

    @Test func evidenceForAnUnknownCandidateIsIgnored() {
        let result = PointingDeixis.resolve(words: PointingDeixis.words(in: "this"),
                                            evidence: [.init(time: 0, candidateID: "zzz"), .init(time: 1, candidateID: nil)],
                                            validIDs: valid)
        #expect(result == [.init(word: "this", candidateID: nil)])
    }

    @Test func noPointingWordsMeansNothingToResolve() {
        let result = PointingDeixis.resolve(words: PointingDeixis.words(in: "open the file menu"),
                                            evidence: [.init(time: 0, candidateID: "t0")], validIDs: valid)
        #expect(result.isEmpty)
    }

    @Test func nonFiniteEvidenceTimeIsIgnored() {
        let result = PointingDeixis.resolve(words: PointingDeixis.words(in: "this"),
                                            evidence: [.init(time: .nan, candidateID: "t0")], validIDs: valid)
        #expect(result.map(\.candidateID) == [nil])
    }

    @Test func theResultIsBounded() {
        let words = PointingDeixis.words(in: String(repeating: "this ", count: 40))
        let result = PointingDeixis.resolve(words: words, evidence: [.init(time: 0, candidateID: "t0")], validIDs: valid)
        #expect(result.count == PointingContext.maxDeixis)
    }
}
