import Testing
import ZeusCore

@Suite("Automation consent cache")
struct AutomationConsentCacheTests {
    private typealias C = AutomationConsentCache
    private let granted = C.noError
    private let needsConsent = C.wouldRequireConsent

    private func run(_ events: [C.Event], from start: C.State = .init()) -> (state: C.State, effects: [[C.Effect]]) {
        var state = start
        var all: [[C.Effect]] = []
        for event in events {
            let (next, effects) = C.reduce(state, event)
            state = next
            all.append(effects)
        }
        return (state, all)
    }

    // MARK: Checks

    @Test func firstReadStartsOneCheckAndLaterReadsDoNotDuplicateIt() {
        let (state, effects) = run([.checkWanted(now: 0), .checkWanted(now: 1), .checkWanted(now: 2)])
        #expect(effects[0] == [.startCheck(generation: 0)])
        #expect(effects[1].isEmpty && effects[2].isEmpty)
        #expect(state.checking)
    }

    @Test func aResolvedAnswerStaysFreshForTheTTLThenReadsAsPending() {
        let (state, _) = run([.checkWanted(now: 0), .checkEnded(generation: 0, code: granted, now: 0.1)])
        #expect(state.status(now: 5) == .granted)
        #expect(state.status(now: 19.9) == .granted)
        #expect(state.status(now: 20.2) == .pending)
        let (rechecked, effects) = C.reduce(state, .checkWanted(now: 21))
        #expect(effects == [.startCheck(generation: 0)])
        #expect(rechecked.checking)
    }

    @Test func aSlowCheckReadsPendingAndIsRetriedOnlyAfterItEnds() {
        let (state, effects) = run([.checkWanted(now: 0), .checkSlow(generation: 0, now: 1), .checkWanted(now: 7)])
        #expect(state.status(now: 7) == .pending)
        #expect(effects[2].isEmpty) // still checking: no parallel check even after the recheck delay
        let (ended, _) = C.reduce(state, .checkEnded(generation: 0, code: nil, now: 8))
        #expect(!ended.checking)
        let (_, again) = C.reduce(ended, .checkWanted(now: 8))
        #expect(again == [.startCheck(generation: 0)])
    }

    @Test func aLateAnswerFromTheCurrentGenerationIsKept() {
        let (state, effects) = run([.checkWanted(now: 0), .checkSlow(generation: 0, now: 1),
                                    .checkEnded(generation: 0, code: granted, now: 3)])
        #expect(state.status(now: 3) == .granted)
        #expect(effects[2] == [.rememberGrant])
        #expect(!state.checking)
    }

    @Test func revokedOrNeverGivenForgetsThePersistedGrant() {
        for code in [C.notPermitted, C.wouldRequireConsent] {
            let (state, effects) = run([.checkWanted(now: 0), .checkEnded(generation: 0, code: code, now: 0.2)])
            #expect(effects[1] == [.forgetGrant])
            #expect(state.status(now: 0.3) == .denied(code: code))
        }
    }

    @Test func anUnrelatedErrorNeitherRemembersNorForgets() {
        let (_, effects) = run([.checkWanted(now: 0), .checkEnded(generation: 0, code: -1, now: 0.2)])
        #expect(effects[1].isEmpty)
    }

    // MARK: The race

    @Test func olderCheckReportingNeedsConsentCannotOverwriteANewerGrant() {
        // A background check starts, the person clicks Allow and the grant is stored, then the older
        // check returns "would require consent". It used to replace the grant and delete the saved one.
        let (state, effects) = run([
            .checkWanted(now: 0),
            .promptBegan,
            .promptAnswered(code: granted, now: 5),
            .checkEnded(generation: 0, code: needsConsent, now: 5.5),
        ])
        #expect(effects[2] == [.rememberGrant])
        #expect(effects[3].isEmpty, "a stale answer must not forget the grant")
        #expect(state.status(now: 6) == .granted)
        #expect(!state.checking)
    }

    @Test func aCheckThatFinishesWhileTheSheetIsUpIsDropped() {
        let (state, effects) = run([
            .checkWanted(now: 0),
            .promptBegan,
            .checkEnded(generation: 0, code: needsConsent, now: 1),
            .promptAnswered(code: granted, now: 9),
        ])
        #expect(effects[2].isEmpty)
        #expect(state.status(now: 10) == .granted)
    }

    @Test func aStaleSlowMarkDoesNotTurnAGrantBackIntoPending() {
        let (state, _) = run([
            .checkWanted(now: 0),
            .promptBegan,
            .promptAnswered(code: granted, now: 2),
            .checkSlow(generation: 0, now: 3),
        ])
        #expect(state.status(now: 3) == .granted)
    }

    @Test func aRefusalInThePromptStillWinsOverAnOlderGrantingCheck() {
        let (state, effects) = run([
            .checkWanted(now: 0),
            .promptBegan,
            .promptAnswered(code: C.notPermitted, now: 4),
            .checkEnded(generation: 0, code: granted, now: 4.5),
        ])
        #expect(effects[2] == [.forgetGrant])
        #expect(effects[3].isEmpty)
        #expect(state.status(now: 5) == .denied(code: C.notPermitted))
    }

    @Test func aCheckStartedAfterThePromptIsCurrentAndApplies() {
        let (afterPrompt, _) = run([.promptBegan, .promptAnswered(code: needsConsent, now: 0)])
        let (_, effects) = run([.checkWanted(now: 30), .checkEnded(generation: 2, code: granted, now: 30.2)],
                               from: afterPrompt)
        #expect(effects[0] == [.startCheck(generation: 2)])
        #expect(effects[1] == [.rememberGrant])
    }

    @Test func eachPromptStepMovesTheGenerationForward() {
        let (state, _) = run([.promptBegan, .promptAnswered(code: granted, now: 1), .promptBegan])
        #expect(state.generation == 3)
    }
}
