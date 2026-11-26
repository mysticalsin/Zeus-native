import Testing
@testable import ZeusCore

func stepZeroAnswer(_ id: String, _ result: StaticString, _ values: [String: ProbeValue] = [:]) -> StepZeroAnswer {
    StepZeroAnswer(id: id, result: ProbeCode(result), values: values)
}

func stepZeroReport(version: String? = nil, answers: [StepZeroAnswer] = []) -> StepZeroReport {
    StepZeroReport(
        createdAt: 1_763_000_000,
        systemVersion: version.map { ProbeTag.accept(.systemVersion, $0) } ?? .withheld(.systemVersion),
        systemBuild: ProbeTag.accept(.systemBuild, "24A335"),
        systemHardware: ProbeTag.accept(.systemHardware, "Mac14,6"),
        zeusVersion: ProbeTag.accept(.zeusVersion, "1.0"),
        buildStamp: ProbeTag.accept(.buildStamp, "20261125000000-1"),
        signing: ProbeCode("adHoc"),
        hardenedRuntime: false,
        sections: [StepZeroSection(id: ProbeCode("P"), state: ProbeCode("notRun"))],
        answers: answers,
        restored: [],
        notPutBack: [],
        grantsAtStart: [],
        leftOn: [],
        takenOff: [],
        summary: []
    )
}

func sealed(_ report: StepZeroReport) -> StepZeroReport {
    var copy = report
    copy.summary = StepZeroSummary.combined([copy])
    return copy
}

@Suite struct StepZeroReportTests {
    @Test func fortyFiveIdsAreUniqueAndSplitByWho() {
        let questions = StepZeroCatalogue.questions
        #expect(questions.count == 45)
        #expect(Set(questions.map(\.id)).count == 45)
        #expect(questions.filter { $0.who == .auto }.count == 12)
        #expect(questions.filter { $0.who == .guided }.count == 24)
        #expect(questions.filter { $0.who == .owner }.count == 9)
    }

    @Test func everyQuestionOfTheSixListsHasAnEntry() {
        let expected: [StepZeroQuestion.Plan: [String]] = [
            .systemSource: (1...11).map { "P\($0)" },
            .lockScreen: (1...12).map { "L\($0)" },
            .earbuds: (1...7).map { "E\($0)" },
            .focus: (1...10).map { "F\($0)" },
            .soundOutput: (1...4).map { "O\($0)" },
            .musicPosition: ["A2"],
        ]
        for plan in StepZeroQuestion.Plan.allCases {
            let ids = StepZeroCatalogue.questions.filter { $0.plan == plan }.map(\.id)
            #expect(ids == expected[plan])
        }
    }

    @Test func fieldIdsAreUniqueInsideEachQuestion() {
        for question in StepZeroCatalogue.questions {
            #expect(Set(question.fields.map(\.id)).count == question.fields.count)
        }
    }
}
