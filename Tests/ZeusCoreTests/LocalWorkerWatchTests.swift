import Testing
@testable import ZeusCore

@Suite("Local worker watchdog")
struct LocalWorkerWatchTests {
    @Test func budgetIsTheExistingFirstAudioGrace() {
        #expect(LocalWorkerWatch.budget() == VoiceTTSChain.firstAudioTimeout + LocalWorkerWatch.grace)
        #expect(LocalWorkerWatch.budget() != 120)
    }

    @Test func silenceThroughTheBudgetIsHung() {
        let limit = LocalWorkerWatch.budget()
        #expect(LocalWorkerWatch.hung(started: 10, now: 10 + limit, budget: limit))
        #expect(LocalWorkerWatch.hung(started: 10, now: 10 + limit - 0.1, budget: limit) == false)
    }

    @Test func aChildThatMissesTheReapDoesNotDisableFutureLaunches() {
        let held = LocalWorkerWatch.afterReap(exited: false)
        #expect(held.blockFutureLaunches == false)
        #expect(held.holdLaunch)
        let gone = LocalWorkerWatch.afterReap(exited: true)
        #expect(gone.blockFutureLaunches == false)
        #expect(gone.holdLaunch == false)
    }
}
