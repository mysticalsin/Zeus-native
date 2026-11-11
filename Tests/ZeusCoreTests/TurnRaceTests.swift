import Testing
@testable import ZeusCore

@Suite struct TurnRaceTests {
    private func racing(deep: DeepTrigger.Reason? = nil) -> (TurnRaceState, [TurnRaceEffect]) {
        var state = TurnRaceState()
        let effects = state.reduce(.released(tiers: ["claude", "codex", "anthropic-api"], deep: deep, atMs: 1_000))
        return (state, effects)
    }

    @Test func everyFastTierStartsTogetherOnRelease() {
        let (state, effects) = racing()
        #expect(effects == [.start(tier: "claude"), .start(tier: "codex"), .start(tier: "anthropic-api")])
        #expect(state.phase == .racing)
    }

    @Test func firstTextWinsAndCancelsTheLosers() {
        var (state, _) = racing()
        let effects = state.reduce(.firstText(tier: "codex", atMs: 1_700))
        #expect(state.winner == "codex")
        #expect(state.phase == .speakingFast)
        #expect(state.winnerLatencyMs == 700)
        #expect(effects == [.cancel(tier: "anthropic-api"), .cancel(tier: "claude")])
    }

    @Test func aLateLoserIsCancelledAndNeverReplacesTheWinner() {
        var (state, _) = racing()
        _ = state.reduce(.firstText(tier: "claude", atMs: 1_500))
        let step1 = state.reduce(.firstText(tier: "codex", atMs: 1_520))
        #expect(step1 == [])
        #expect(state.winner == "claude")
    }

    @Test func fillerAtNineHundredMillisecondsOnceWhenNothingStreamed() {
        var (state, _) = racing()
        let step2 = state.reduce(.tick(atMs: 1_850))
        #expect(step2 == [])
        let step3 = state.reduce(.tick(atMs: 1_900))
        #expect(step3 == [.speakFiller])
        let step4 = state.reduce(.tick(atMs: 2_500))
        #expect(step4 == [])
    }

    @Test func noFillerWhenAnAnswerAlreadyStreamed() {
        var (state, _) = racing()
        _ = state.reduce(.firstText(tier: "claude", atMs: 1_400))
        let step5 = state.reduce(.tick(atMs: 2_000))
        #expect(step5 == [])
    }

    @Test func allTiersFailingGivesOneSpokenErrorImmediately() {
        var (state, _) = racing()
        let step6 = state.reduce(.tierFailed(tier: "claude", atMs: 2_000))
        #expect(step6 == [])
        let step7 = state.reduce(.tierFailed(tier: "codex", atMs: 2_100))
        #expect(step7 == [])
        let step8 = state.reduce(.tierFailed(tier: "anthropic-api", atMs: 2_200))
        #expect(step8 == [.speakError(.allFailed)])
        #expect(state.phase == .failed)
        let step9 = state.reduce(.tick(atMs: 9_500))
        #expect(step9 == [])
    }

    @Test func silenceFailsWithinEightSecondsAndStopsEveryTier() {
        var (state, _) = racing()
        let step10 = state.reduce(.tick(atMs: 8_999)).contains(.speakError(.timeout))
        #expect(step10 == false)
        let effects = state.reduce(.tick(atMs: 9_000))
        #expect(effects.filter { $0 == .speakError(.timeout) }.count == 1)
        #expect(effects.contains(.cancel(tier: "claude")) && effects.contains(.cancel(tier: "codex")))
        #expect(state.failure == .timeout)
        #expect(FastTier.firstTextBudgetMs <= 8_000)
    }

    @Test func noReachableTierIsOneClearError() {
        var state = TurnRaceState()
        let step11 = state.reduce(.released(tiers: [], deep: nil, atMs: 0))
        #expect(step11 == [.speakError(.noTier)])
    }

    @Test func deepStartsInTheBackgroundWithoutBlockingTheFastAnswer() {
        var (state, _) = racing(deep: .complexity)
        let effects = state.reduce(.firstText(tier: "claude", atMs: 1_400))
        #expect(effects.contains(.startDeep))
        #expect(state.phase == .speakingFast)
        let step12 = state.reduce(.fastFinished(atMs: 2_000))
        #expect(step12 == [])
        #expect(state.phase == .deepPending)
        let step13 = state.reduce(.deepAnswer(text: "Fuller."))
        #expect(step13 == [.deliverDeep(text: "Fuller.")])
        #expect(state.phase == .done)
    }

    @Test func aDeepAnswerThatBeatsTheFastOneWaitsForIt() {
        var (state, _) = racing(deep: .explicit)
        _ = state.reduce(.firstText(tier: "claude", atMs: 1_400))
        let step14 = state.reduce(.deepAnswer(text: "Fuller."))
        #expect(step14 == [])
        let step15 = state.reduce(.fastFinished(atMs: 3_000))
        #expect(step15 == [.deliverDeep(text: "Fuller.")])
        #expect(state.phase == .done)
    }

    @Test func noDeepWhenNotWanted() {
        var (state, _) = racing()
        _ = state.reduce(.firstText(tier: "claude", atMs: 1_400))
        _ = state.reduce(.fastFinished(atMs: 1_900))
        #expect(state.phase == .done)
        let step16 = state.reduce(.deepAnswer(text: "x"))
        #expect(step16 == [])
    }

    @Test func aFailedDeepNeverSpeaksAnError() {
        var (state, _) = racing(deep: .complexity)
        _ = state.reduce(.firstText(tier: "claude", atMs: 1_400))
        _ = state.reduce(.fastFinished(atMs: 2_000))
        let step17 = state.reduce(.deepFailed)
        #expect(step17 == [])
        #expect(state.phase == .done)
    }

    @Test func aNewPressCancelsRacersAndDeep() {
        var (state, _) = racing(deep: .complexity)
        _ = state.reduce(.firstText(tier: "claude", atMs: 1_400))
        _ = state.reduce(.fastFinished(atMs: 2_000))
        let step18 = state.reduce(.cancelled)
        #expect(step18 == [.cancelDeep])
        let step19 = state.reduce(.deepAnswer(text: "late"))
        #expect(step19 == [])
        var mid = racing().0
        let effects = mid.reduce(.cancelled)
        #expect(effects.count == 3 && effects.allSatisfy { if case .cancel = $0 { true } else { false } })
    }

    @Test func winnerFailingAfterSpeakingKeepsThePartialAnswer() {
        var (state, _) = racing()
        _ = state.reduce(.firstText(tier: "claude", atMs: 1_400))
        let step20 = state.reduce(.tierFailed(tier: "claude", atMs: 2_000))
        #expect(step20 == [])
        #expect(state.phase == .speakingFast)
    }

    @Test func fastRaceSkipsSlowEnginesAndColdOllama() {
        let order: [BrainEngineID] = [.ollamaHTTP, .codex, .gemini, .claude, .ollama, .grok, .cursorAgent]
        #expect(FastTier.fastRace(order: order, ollamaWarm: false) == [.claude, .codex])
        #expect(FastTier.fastRace(order: order, ollamaWarm: true) == [.claude, .codex, .ollamaHTTP])
        #expect(FastTier.fastRace(order: [.anthropicAPI, .openAIAPI, .claude, .codex], ollamaWarm: false)
                == [.anthropicAPI, .openAIAPI, .claude, .codex])
        #expect(FastTier.fastRace(order: [.gemini, .cursorAgent], ollamaWarm: false).isEmpty)
    }

    @Test func deepEnginePrefersSonnetOverApiThenCli() {
        #expect(FastTier.deepEngine(order: [.codex, .claude, .anthropicAPI]) == .anthropicAPI)
        #expect(FastTier.deepEngine(order: [.codex, .claude]) == .claude)
        #expect(FastTier.deepEngine(order: [.gemini]) == nil)
    }

    @Test func deepTriggerHeuristic() {
        #expect(DeepTrigger.reason(for: "Zeus think harder about this", task: .quickAnswer) == .explicit)
        #expect(DeepTrigger.reason(for: "what time is it in Paris", task: .quickAnswer) == nil)
        #expect(DeepTrigger.reason(for: "explain how the new pricing model affects our margin on all of the bids", task: .quickAnswer) == .complexity)
        #expect(DeepTrigger.reason(for: "fix the login bug", task: .code) == .complexity)
        #expect(DeepTrigger.reason(for: "explain my private notes in detail", task: .privateLocal) == nil)
        #expect(DeepTrigger.reason(for: "explain my private notes to me please now", task: .privateLocal) == nil)
    }
}
