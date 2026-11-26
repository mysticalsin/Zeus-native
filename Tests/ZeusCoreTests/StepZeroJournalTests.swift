import Foundation
import Testing
@testable import ZeusCore

@Suite struct StepZeroJournalTests {
    @Test func aStepLeftStartedBecomesEndedProcess() {
        let journal = StepZeroJournal(
            steps: [
                StepZeroJournal.Step(part: "E5", mark: "started"),
                StepZeroJournal.Step(part: "P1", mark: "finished"),
                StepZeroJournal.Step(part: "L2", mark: "started"),
                StepZeroJournal.Step(part: "L2", mark: "finished"),
            ],
            childPid: 4242,
            owedRestore: nil,
            grantsAtStart: [],
            bootMark: nil
        )
        let resume = journal.resume()
        #expect(resume.endedProcess == ["E5"])
        #expect(resume.nextPart == "E5")
        #expect(resume.childPid == 4242)
        let data = StepZeroJournalCodec.encode(journal)
        #expect(StepZeroJournalCodec.decode(data!) == journal)
    }

    @Test func aForgedEntryDiscardsTheJournal() {
        let text = encoded(sample())
        #expect(StepZeroJournalCodec.decode(Data(text.replacing("\"E5\"", with: "\"ZZ\"").utf8)) == nil)
        #expect(StepZeroJournalCodec.decode(Data(text.replacing("}", with: ",\"note\":\"x\"}").utf8)) == nil)
        #expect(StepZeroJournalCodec.decode(Data(text.replacing("\"started\"", with: "\"paused\"").utf8)) == nil)
    }

    @Test func theOwedRestoreSurvives() {
        var journal = sample()
        journal.owedRestore = 2
        let decoded = StepZeroJournalCodec.decode(StepZeroJournalCodec.encode(journal)!)
        #expect(decoded?.owedRestore == 2)
        #expect(decoded?.resume().putBack == 2)
        #expect(decoded?.resume().endedProcess == ["E5"])
    }

    @Test func aBootMarkThatIsNotSixteenHexDigitsIsDiscarded() {
        var journal = sample()
        journal.owedRestore = 3
        journal.bootMark = "0123456789abcdef"
        let kept = StepZeroJournalCodec.decode(StepZeroJournalCodec.encode(journal)!)
        #expect(kept?.bootMark == "0123456789abcdef")
        let text = String(decoding: StepZeroJournalCodec.encode(journal)!, as: UTF8.self)
        let broken = text.replacing("0123456789abcdef", with: "zzzzzzzzzzzzzzzz")
        let decoded = StepZeroJournalCodec.decode(Data(broken.utf8))
        #expect(decoded != nil)
        #expect(decoded?.bootMark == nil)
        #expect(decoded?.steps.map(\.part) == ["E5"])
        #expect(decoded?.owedRestore == 3)
    }
}

private func sample() -> StepZeroJournal {
    StepZeroJournal(
        steps: [StepZeroJournal.Step(part: "E5", mark: "started")],
        childPid: nil,
        owedRestore: nil,
        grantsAtStart: [StepZeroGrantReading(grant: ProbeCode("bluetooth"), state: ProbeCode("off"))],
        bootMark: nil
    )
}

private func encoded(_ journal: StepZeroJournal) -> String {
    String(decoding: StepZeroJournalCodec.encode(journal)!, as: UTF8.self)
}
