import Testing
@testable import ZeusCore

@Suite struct TurnRaceLiveTierTests {
    private func racing(deep: DeepTrigger.Reason? = nil) -> TurnRaceState {
        var state = TurnRaceState()
        _ = state.reduce(.released(tiers: ["claude", "codex"], deep: deep, atMs: 1_000))
        return state
    }

    @Test func aCancelledLoserIsNoLongerLiveSoItsLateErrorIsNotAFailure() {
        var state = racing()
        #expect(state.isLive("claude") && state.isLive("codex"))
        _ = state.reduce(.firstText(tier: "claude", atMs: 1_400))
        #expect(state.isLive("claude"))
        #expect(!state.isLive("codex"))
        let late = state.reduce(.tierFailed(tier: "codex", atMs: 1_450))
        #expect(late == [])
        #expect(state.tiers["codex"] == .cancelled)
    }

    @Test func aTierThatFailedIsNotLiveAndAnUnknownTierNeverIs() {
        var state = racing()
        _ = state.reduce(.tierFailed(tier: "codex", atMs: 1_200))
        #expect(!state.isLive("codex"))
        #expect(!state.isLive("nobody"))
    }

    @Test func theWinnerBreakingOffCancelsTheDeepAnswerBehindIt() {
        var state = racing(deep: .complexity)
        _ = state.reduce(.firstText(tier: "claude", atMs: 1_400))
        #expect(state.deepRunning)
        let effects = state.reduce(.tierFailed(tier: "claude", atMs: 2_000))
        #expect(effects == [.cancelDeep])
        #expect(!state.deepRunning)
        let held = state.reduce(.deepAnswer(text: "late"))
        #expect(held == [])
    }

    @Test func theWinnerBreakingOffDropsADeepAnswerAlreadyHeld() {
        var state = racing(deep: .explicit)
        _ = state.reduce(.firstText(tier: "claude", atMs: 1_400))
        _ = state.reduce(.deepAnswer(text: "fuller"))
        _ = state.reduce(.tierFailed(tier: "claude", atMs: 2_000))
        let finished = state.reduce(.fastFinished(atMs: 2_100))
        #expect(finished == [])
    }
}
