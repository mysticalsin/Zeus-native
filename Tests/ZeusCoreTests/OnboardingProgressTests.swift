import Testing
import ZeusCore

@Suite("Onboarding progress")
struct OnboardingProgressTests {
    private typealias P = OnboardingProgress

    @Test func firstPresentationStartsTheGuide() {
        let (state, effects) = P.reduce(.notStarted, .presented)
        #expect(state == .inProgress)
        #expect(effects.isEmpty)
    }

    @Test func closingTheWindowBeforeTheEndRecordsADismissal() {
        let (state, effects) = P.reduce(.inProgress, .windowClosed)
        #expect(state == .dismissed)
        #expect(effects == [.recordDismissed])
    }

    @Test func setUpLaterOnAMiddleStepOnlySkipsThatStep() {
        let (state, effects) = P.reduce(.inProgress, .skippedStep(onLastStep: false))
        #expect(state == .inProgress)
        #expect(effects.isEmpty)
    }

    @Test func setUpLaterOnTheLastReachableStepRecordsADismissal() {
        let (state, effects) = P.reduce(.inProgress, .skippedStep(onLastStep: true))
        #expect(state == .dismissed)
        #expect(effects == [.recordDismissed])
    }

    @Test func finishingCompletesAndRecordsItOnce() {
        let (done, effects) = P.reduce(.inProgress, .finished)
        #expect(done == .completed)
        #expect(effects == [.recordCompleted])
        let (again, repeated) = P.reduce(done, .finished)
        #expect(again == .completed)
        #expect(repeated.isEmpty)
    }

    @Test func theWindowClosingAfterFinishDoesNotDemoteCompletion() {
        let (state, effects) = P.reduce(.completed, .windowClosed)
        #expect(state == .completed)
        #expect(effects.isEmpty)
    }

    @Test func aDismissalIsRecordedOnlyOnce() {
        let (state, effects) = P.reduce(.dismissed, .windowClosed)
        #expect(state == .dismissed)
        #expect(effects.isEmpty)
        let (reopened, none) = P.reduce(.dismissed, .presented)
        #expect(reopened == .dismissed)
        #expect(none.isEmpty)
    }

    @Test func aReopenedDismissedGuideCanStillBeFinished() {
        let (state, effects) = P.reduce(.dismissed, .finished)
        #expect(state == .completed)
        #expect(effects == [.recordCompleted])
    }

    @Test func savedFlagsMapToStates() {
        #expect(P.saved(completed: false, dismissed: false) == .notStarted)
        #expect(P.saved(completed: false, dismissed: true) == .dismissed)
        #expect(P.saved(completed: true, dismissed: true) == .completed)
        #expect(P.saved(completed: true, dismissed: false) == .completed)
    }

    @Test func launchReopensOnlyAGuideNeitherFinishedNorDismissed() {
        #expect(P.opensAtLaunch(.notStarted, explicitStepRequested: false))
        #expect(P.opensAtLaunch(.inProgress, explicitStepRequested: false))
        #expect(!P.opensAtLaunch(.dismissed, explicitStepRequested: false))
        #expect(!P.opensAtLaunch(.completed, explicitStepRequested: false))
    }

    @Test func anExplicitStepRequestAlwaysOpensTheGuide() {
        #expect(P.opensAtLaunch(.dismissed, explicitStepRequested: true))
        #expect(P.opensAtLaunch(.completed, explicitStepRequested: true))
    }

    @Test func closingOnStepThreeThenRelaunchingDoesNotReopen() {
        // The reported scenario: close the guide midway, quit, launch again.
        var state = P.saved(completed: false, dismissed: false)
        state = P.reduce(state, .presented).0
        let (closed, effects) = P.reduce(state, .windowClosed)
        #expect(effects == [.recordDismissed])
        let relaunch = P.saved(completed: false, dismissed: effects.contains(.recordDismissed))
        #expect(relaunch == closed)
        #expect(!P.opensAtLaunch(relaunch, explicitStepRequested: false))
    }
}
