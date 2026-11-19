import Testing
import ZeusCore

@Suite("Microphone test state")
struct MicTestTests {
    private typealias T = MicTest

    private func running(_ session: UInt64 = 1, level: Double = 0, peak: Double = 0, note: String? = nil) -> T.State {
        .running(session: session, level: level, peak: peak, note: note)
    }

    // MARK: Legal transitions

    @Test func openingFromIdleStartsAFreshTest() {
        let (state, effects) = T.reduce(.idle, .opened(session: 1, note: nil))
        #expect(state == running(1))
        #expect(effects.isEmpty)
        #expect(state.isRunning)
    }

    @Test func aNoteRidesAlongWithoutStoppingTheTest() {
        let (state, _) = T.reduce(.idle, .opened(session: 1, note: "Using the system input."))
        #expect(state.isRunning)
        #expect(state.problem == "Using the system input.")
    }

    @Test func levelsUpdateTheLevelAndKeepThePeak() {
        let (a, _) = T.reduce(running(1), .level(session: 1, value: 0.6))
        let (b, _) = T.reduce(a, .level(session: 1, value: 0.2))
        #expect(b == running(1, level: 0.2, peak: 0.6))
        #expect(b.level == 0.2)
        #expect(b.peak == 0.6)
    }

    @Test func stopKeepsThePeakForTheVerdictAndReleasesCapture() {
        let (state, effects) = T.reduce(running(1, level: 0.1, peak: 0.5), .stopRequested)
        #expect(state == .finished(peak: 0.5, note: nil))
        #expect(effects == [.stopCapture])
        #expect(state.level == 0)
        #expect(state.verdict == "Sounds good.")
    }

    @Test func timerEndsTheLiveSessionLikeStop() {
        let (state, effects) = T.reduce(running(2, peak: 0.03), .timedOut(session: 2))
        #expect(state == .finished(peak: 0.03, note: nil))
        #expect(effects == [.stopCapture])
        #expect(state.verdict == "Too quiet. Move closer or pick another microphone.")
    }

    @Test func noVerdictWhileRunningOrWhenNothingWasHeard() {
        #expect(running(1, peak: 0.5).verdict == nil)
        #expect(T.State.finished(peak: 0, note: nil).verdict == nil)
        #expect(T.State.idle.verdict == nil)
    }

    @Test func startFailureShowsTheProblemWithNoStalePeak() {
        let (state, effects) = T.reduce(.finished(peak: 0.9, note: nil), .failed(session: 2, problem: "No microphone is connected."))
        #expect(state == .failed("No microphone is connected."))
        #expect(effects.isEmpty)
        #expect(state.peak == 0)
        #expect(state.verdict == nil)
    }

    // MARK: Illegal events, double start

    @Test func secondEngineOpeningDuringARunningTestIsDiscarded() {
        let live = running(1, peak: 0.4)
        let (state, effects) = T.reduce(live, .opened(session: 2, note: nil))
        #expect(state == live)
        #expect(effects == [.discardCapture(session: 2)])
    }

    @Test func failedStartNeverReplacesARunningTest() {
        let live = running(1, peak: 0.4)
        #expect(T.reduce(live, .failed(session: 2, problem: "late")).0 == live)
    }

    @Test func levelsWhileNotRunningAreIgnored() {
        for resting in [T.State.idle, .finished(peak: 0.3, note: nil), .failed("x")] {
            #expect(T.reduce(resting, .level(session: 1, value: 0.9)).0 == resting)
        }
    }

    // MARK: Stale completion

    @Test func levelFromAnEarlierTestCannotInflateTheNewPeak() {
        let (second, _) = T.reduce(.finished(peak: 0.2, note: nil), .opened(session: 2, note: nil))
        let (after, effects) = T.reduce(second, .level(session: 1, value: 1.0))
        #expect(after == running(2))
        #expect(effects.isEmpty)
        #expect(after.peak == 0)
    }

    @Test func oldTimerCannotEndANewerTest() {
        let live = running(2, peak: 0.4)
        let (state, effects) = T.reduce(live, .timedOut(session: 1))
        #expect(state == live)
        #expect(effects.isEmpty)
    }

    @Test func timerAfterManualStopChangesNothing() {
        let (stopped, _) = T.reduce(running(1, peak: 0.5), .stopRequested)
        let (state, effects) = T.reduce(stopped, .timedOut(session: 1))
        #expect(state == stopped)
        #expect(effects.isEmpty)
    }

    // MARK: Cancel from each state

    @Test func stopFromEveryRestingStateIsANoOp() {
        for resting in [T.State.idle, .finished(peak: 0.3, note: nil), .failed("x")] {
            let (state, effects) = T.reduce(resting, .stopRequested)
            #expect(state == resting)
            #expect(effects.isEmpty)
        }
    }

    @Test func stopFromRunningAlwaysReachesATerminalStateAndReleases() {
        let (state, effects) = T.reduce(running(7, level: 0.9, peak: 0.9), .stopRequested)
        #expect(!state.isRunning)
        #expect(effects == [.stopCapture])
    }

    // MARK: Failure then retry

    @Test func retryAfterFailureOpensANewTest() {
        let (failed, _) = T.reduce(.idle, .failed(session: 1, problem: "Allow the microphone for ZEUS first."))
        let (retry, _) = T.reduce(failed, .opened(session: 2, note: nil))
        #expect(retry == running(2))
        #expect(retry.problem == nil)
    }
}
