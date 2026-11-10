import Testing
import ZeusCore

@Suite("dictate-file E2E reply")
struct DictationFileInjectTests {
    @Test func targetStateIsReadyOnlyWhenTargetFrontmostAndFocusAgree() {
        #expect(DictationFileInject.targetState(target: 10, frontmost: 10, focus: 10) == .ready)
    }

    @Test func targetStateFailsClosedForEveryUnknownAndNegativeInput() {
        typealias Inject = DictationFileInject
        #expect(Inject.targetState(target: nil, frontmost: 10, focus: 10) == .unavailable)
        #expect(Inject.targetState(target: nil, frontmost: nil, focus: nil) == .unavailable)
        #expect(Inject.targetState(target: 10, frontmost: nil, focus: 10) == .frontmostUnavailable)
        #expect(Inject.targetState(target: 10, frontmost: 11, focus: 10) == .frontmostDrift)
        #expect(Inject.targetState(target: 10, frontmost: 10, focus: nil) == .focusUnavailable)
        #expect(Inject.targetState(target: 10, frontmost: 10, focus: 11) == .focusDrift)
        // Frontmost is judged before focus.
        #expect(Inject.targetState(target: 10, frontmost: 11, focus: nil) == .frontmostDrift)
    }

    @Test func okWhenInserted() {
        #expect(DictationFileInject.reply(inserted: true, resultText: "quick brown fox", failureMessage: nil) == "ok")
    }

    @Test func errorWhenEmptyTranscript() {
        #expect(DictationFileInject.reply(inserted: false, resultText: "", failureMessage: "No speech was heard.") == "ERROR No speech was heard.")
    }

    @Test func errorWhenNotInserted() {
        #expect(DictationFileInject.reply(inserted: false, resultText: "hello", failureMessage: nil) == "ERROR nothing inserted")
    }

    @Test func staleHistoryDoesNotProduceOk() {
        let prior = DictationFileInject.TurnSnapshot(inserted: true, resultText: "Meet me at 4 PM")
        #expect(DictationFileInject.replyAfterInject(historyCountBefore: 1,
                                                     history: [prior],
                                                     failureMessage: nil) == "ERROR nothing inserted")
    }

    @Test func failedTurnUsesFailureNotStaleOk() {
        let prior = DictationFileInject.TurnSnapshot(inserted: true, resultText: "old clip")
        #expect(DictationFileInject.replyAfterInject(historyCountBefore: 1,
                                                     history: [prior],
                                                     failureMessage: "No speech was heard.")
            == "ERROR No speech was heard.")
    }

    @Test func freshTurnUsesNewHead() {
        let prior = DictationFileInject.TurnSnapshot(inserted: true, resultText: "old")
        let fresh = DictationFileInject.TurnSnapshot(inserted: true, resultText: "quick brown fox")
        #expect(DictationFileInject.replyAfterInject(historyCountBefore: 1,
                                                     history: [fresh, prior],
                                                     failureMessage: nil) == "ok")
    }

    @Test func fieldMatchIgnoresCaseAndPeriods() {
        let expected = "The quick brown fox jumps over the lazy dog."
        #expect(DictationFileInject.fieldMatches("The quick brown fox jumps over the lazy dog", expected: expected))
        #expect(!DictationFileInject.fieldMatches("", expected: expected))
    }

    @Test func okRequiresVisiblePasteWhenFieldProvided() {
        let turn = DictationFileInject.TurnSnapshot(inserted: true, resultText: "quick brown fox jumps over the lazy dog")
        #expect(DictationFileInject.replyAfterInject(historyCountBefore: 0,
                                                     history: [turn],
                                                     failureMessage: nil,
                                                     fieldText: "The quick brown fox jumps over the lazy dog") == "ok")
        #expect(DictationFileInject.replyAfterInject(historyCountBefore: 0,
                                                     history: [turn],
                                                     failureMessage: nil,
                                                     fieldText: "") == "ERROR paste not verified")
    }
}
