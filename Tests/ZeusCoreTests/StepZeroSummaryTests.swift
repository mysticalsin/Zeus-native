import Testing
@testable import ZeusCore

@Suite struct StepZeroSummaryTests {
    @Test func eachStopRule() {
        let missed = stepZeroReport(answers: [
            stepZeroAnswer("P1", "no", ["p1.itemSeen": .flag(false), "p1.ownerSaysPlaying": .flag(true)]),
        ])
        #expect(plan(missed, .systemSource).word == .stop)

        let locked = stepZeroReport(version: "27.0", answers: [
            stepZeroAnswer("L2", "no"), stepZeroAnswer("L3", "yes"), stepZeroAnswer("L4", "yes", ["l4.cycles": .count(20)]),
        ])
        #expect(plan(locked, .lockScreen).word == .stop)

        let battery = stepZeroReport(answers: [stepZeroAnswer("E2", "no"), stepZeroAnswer("E5", "yes")])
        #expect(plan(battery, .earbuds).word == .stop)
        let mode = stepZeroReport(answers: [stepZeroAnswer("E2", "yes"), stepZeroAnswer("E5", "no")])
        #expect(plan(mode, .earbuds).word == .stop)

        let quiet = stepZeroReport(answers: [
            stepZeroAnswer("F2", "no", ["f2.changeSeen": .flag(false), "f2.hasModeIdKey": .flag(true), "f2.idIsConfigKey": .flag(true)]),
        ])
        #expect(plan(quiet, .focus).word == .stop)
        let missingKey = stepZeroReport(answers: [
            stepZeroAnswer("F2", "yes", ["f2.changeSeen": .flag(true), "f2.hasModeIdKey": .flag(false), "f2.idIsConfigKey": .flag(true)]),
        ])
        #expect(plan(missingKey, .focus).word == .stop)

        let sound = stepZeroReport(answers: ["O1", "O2", "O3", "O4"].map { stepZeroAnswer($0, "no") })
        #expect(plan(sound, .soundOutput).word == .go)
        let music = stepZeroReport(answers: [stepZeroAnswer("A2", "no")])
        #expect(plan(music, .musicPosition).word == .go)
    }

    @Test func p1YesOnAttemptBAloneIsGo() {
        let report = stepZeroReport(answers: [
            stepZeroAnswer("P1", "yes", ["p1.itemSeen": .flag(true), "p1.ownerSaysPlaying": .flag(false)]),
            stepZeroAnswer("P5", "yes", ["p5.emptyEnvOK": .flag(false), "p5.needs": .code(ProbeCode("homeUserTmp"))]),
        ])
        #expect(plan(report, .systemSource).word == .go)
    }

    @Test func threeMissesWithoutTheOwnersYesIsOpen() {
        let report = stepZeroReport(answers: [
            stepZeroAnswer("P1", "no", ["p1.itemSeen": .flag(false), "p1.ownerSaysPlaying": .flag(false)]),
        ])
        let summary = plan(report, .systemSource)
        #expect(summary.word == .open)
        #expect(summary.reasons.map(\.raw).contains("unanswered"))
    }

    @Test func lockCyclesMacsAndASkip() {
        let short = lock("27.0", cycles: 19)
        let shortSummary = plan(short, .lockScreen)
        #expect(shortSummary.word == .open)
        #expect(shortSummary.reasons.map(\.raw).contains("cycles"))

        let one = lock("27.0", cycles: 20)
        let oneSummary = plan(one, .lockScreen)
        #expect(oneSummary.word == .open)
        #expect(oneSummary.reasons.map(\.raw).contains("secondMac"))

        let both = StepZeroSummary.combined([lock("27.1", cycles: 20), lock("26.2", cycles: 20)])
        #expect(both.first { $0.plan == .lockScreen }?.word == .go)

        var skipped = lock("27.0", cycles: 20)
        skipped.answers[0] = stepZeroAnswer("L2", "skipped")
        let pair = StepZeroSummary.combined([skipped, lock("26.0", cycles: 20)])
        let skipSummary = pair.first { $0.plan == .lockScreen }!
        #expect(skipSummary.word == .open)
        #expect(skipSummary.reasons.map(\.raw).contains("skipped"))
    }

    @Test func noWordHoldsADash() {
        let em = Character(UnicodeScalar(0x2014)!)
        let en = Character(UnicodeScalar(0x2013)!)
        var texts = ProbeLexicon.words
        texts += StepZeroCatalogue.questions.flatMap { question in
            [question.id] + question.fields.map(\.id)
        }
        texts += StepZeroQuestion.Plan.allCases.map(\.rawValue)
        texts += StepZeroQuestion.Who.allCases.map(\.rawValue)
        texts += StepZeroQuestion.Prompt.allCases.map(\.rawValue)
        texts += StepZeroQuestion.Need.allCases.map(\.rawValue)
        texts += PlanSummary.Word.allCases.map(\.rawValue)
        texts += ProbeTag.Field.allCases.map(\.rawValue)
        #expect(texts.allSatisfy { $0.contains(em) == false && $0.contains(en) == false })
    }
}

private func plan(_ report: StepZeroReport, _ id: StepZeroQuestion.Plan) -> PlanSummary {
    StepZeroSummary.combined([report]).first { $0.plan == id }!
}

private func lock(_ version: String, cycles: Int) -> StepZeroReport {
    stepZeroReport(version: version, answers: [
        stepZeroAnswer("L2", "yes"),
        stepZeroAnswer("L3", "yes"),
        stepZeroAnswer("L4", "yes", ["l4.cycles": .count(cycles)]),
    ])
}
