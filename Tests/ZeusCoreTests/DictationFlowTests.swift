import Testing
import ZeusCore

@Suite("Dictation job flow")
struct DictationFlowTests {
    private typealias F = DictationFlow

    private let allStates: [F.State] = [
        .idle, .listening(turn: 1), .transcribing(turn: 1, source: .live), .transcribing(turn: 1, source: .file),
        .rewriting(turn: 1, source: .live), .rewriting(turn: 1, source: .history), .done, .failed("x"),
    ]

    // MARK: Legal transitions

    @Test func micOpensFromEveryRestingState() {
        for resting in [F.State.idle, .done, .failed("old")] {
            let (state, effects) = F.reduce(resting, .micOpened(turn: 4))
            #expect(state == .listening(turn: 4))
            #expect(effects.isEmpty)
        }
    }

    @Test func finishMovesListeningToTranscribing() {
        let (state, _) = F.reduce(.listening(turn: 4), .finishRequested)
        #expect(state == .transcribing(turn: 4, source: .live))
        #expect(state.phase == .transcribing)
    }

    @Test func liveTurnRewritesThenSucceeds() {
        let (rewriting, _) = F.reduce(.transcribing(turn: 4, source: .live), .rewriteStarted(turn: 4, source: .live))
        #expect(rewriting == .rewriting(turn: 4, source: .live))
        #expect(rewriting.phase == .rewriting)
        let (done, _) = F.reduce(rewriting, .succeeded(turn: 4))
        #expect(done == .done)
    }

    @Test func liveTurnWithoutRewriteSucceedsFromTranscribing() {
        #expect(F.reduce(.transcribing(turn: 4, source: .live), .succeeded(turn: 4)).0 == .done)
    }

    @Test func emptyResultFailsTheLiveTurn() {
        let (state, _) = F.reduce(.transcribing(turn: 4, source: .live), .failed(turn: 4, reason: "No speech was heard."))
        #expect(state == .failed("No speech was heard."))
        #expect(state.phase == .failed("No speech was heard."))
    }

    @Test func discardedTurnReturnsToIdle() {
        #expect(F.reduce(.transcribing(turn: 4, source: .live), .dismissed(turn: 4)).0 == .idle)
        #expect(F.reduce(.rewriting(turn: 4, source: .live), .dismissed(turn: 4)).0 == .idle)
    }

    @Test func fileJobRunsTranscribingThenDone() {
        let (running, _) = F.reduce(.idle, .fileRequested(turn: 9))
        #expect(running == .transcribing(turn: 9, source: .file))
        #expect(F.reduce(running, .succeeded(turn: 9)).0 == .done)
        #expect(F.reduce(running, .failed(turn: 9, reason: "No speech found in the file.")).0 == .failed("No speech found in the file."))
    }

    @Test func historyRerunEntersRewritingFromRestAndLeavesQuietly() {
        let (rewriting, _) = F.reduce(.idle, .rewriteStarted(turn: 6, source: .history))
        #expect(rewriting == .rewriting(turn: 6, source: .history))
        #expect(F.reduce(rewriting, .dismissed(turn: 6)).0 == .idle)
    }

    @Test func startFailureShowsTheReasonFromRest() {
        #expect(F.reduce(.idle, .startFailed(reason: "no mic")).0 == .failed("no mic"))
    }

    @Test func phaseMatchesWhatTheNotchShows() {
        let phases = allStates.map(\.phase)
        #expect(phases == [.idle, .listening, .transcribing, .transcribing, .rewriting, .rewriting, .done, .failed("x")])
    }

    // MARK: Illegal events and double start

    @Test func doubleStartWhileListeningIsRefused() {
        let (state, effects) = F.reduce(.listening(turn: 1), .micOpened(turn: 2))
        #expect(state == .listening(turn: 1))
        #expect(effects == [.busy])
    }

    @Test func fileWhileListeningCannotTakeThePhaseFromTheMicrophone() {
        let (state, effects) = F.reduce(.listening(turn: 1), .fileRequested(turn: 2))
        #expect(state == .listening(turn: 1))
        #expect(effects == [.busy])
    }

    @Test func secondFileWhileOneRunsIsRefused() {
        let running = F.State.transcribing(turn: 2, source: .file)
        let (state, effects) = F.reduce(running, .fileRequested(turn: 3))
        #expect(state == running)
        #expect(effects == [.busy])
    }

    @Test func micCannotOpenDuringAFileOrRewrite() {
        for active in [F.State.transcribing(turn: 2, source: .file), .transcribing(turn: 2, source: .live),
                       .rewriting(turn: 2, source: .live), .rewriting(turn: 2, source: .history)] {
            let (state, effects) = F.reduce(active, .micOpened(turn: 3))
            #expect(state == active)
            #expect(effects == [.busy])
        }
    }

    @Test func startFailureNeverReplacesARunningJob() {
        for active in allStates where active.isActive {
            #expect(F.reduce(active, .startFailed(reason: "late")).0 == active)
        }
    }

    @Test func finishIsIgnoredUnlessListening() {
        for state in allStates where !state.isListening {
            let (next, effects) = F.reduce(state, .finishRequested)
            #expect(next == state)
            #expect(effects.isEmpty)
        }
    }

    @Test func listeningCannotCompleteBeforeItIsFinished() {
        let listening = F.State.listening(turn: 1)
        #expect(F.reduce(listening, .succeeded(turn: 1)).0 == listening)
        #expect(F.reduce(listening, .failed(turn: 1, reason: "x")).0 == listening)
        #expect(F.reduce(listening, .dismissed(turn: 1)).0 == listening)
    }

    @Test func rewriteIsRefusedWhileAnotherJobOwnsThePhase() {
        for active in [F.State.listening(turn: 2), .transcribing(turn: 2, source: .file), .rewriting(turn: 2, source: .live)] {
            #expect(F.reduce(active, .rewriteStarted(turn: 5, source: .history)).0 == active)
        }
        // A live rewrite only follows its own transcribing turn.
        let file = F.State.transcribing(turn: 2, source: .file)
        #expect(F.reduce(file, .rewriteStarted(turn: 2, source: .live)).0 == file)
        #expect(F.reduce(.idle, .rewriteStarted(turn: 2, source: .live)).0 == .idle)
    }

    // MARK: Stale completion

    @Test func staleCompletionsAreDroppedInEveryActiveState() {
        for active in [F.State.transcribing(turn: 8, source: .file), .transcribing(turn: 8, source: .live), .rewriting(turn: 8, source: .history)] {
            #expect(F.reduce(active, .succeeded(turn: 7)).0 == active)
            #expect(F.reduce(active, .failed(turn: 7, reason: "old")).0 == active)
            #expect(F.reduce(active, .dismissed(turn: 7)).0 == active)
        }
    }

    @Test func firstFileFinishingCannotMarkTheSecondFileDone() {
        // File 2 cancelled file 1 and took over: file 1's late completion carries the old token.
        let (cancelled, _) = F.reduce(.transcribing(turn: 1, source: .file), .cancelRequested)
        let (second, _) = F.reduce(cancelled, .fileRequested(turn: 2))
        #expect(F.reduce(second, .succeeded(turn: 1)).0 == second)
    }

    @Test func completionsAtRestChangeNothing() {
        for resting in [F.State.idle, .done, .failed("x")] {
            #expect(F.reduce(resting, .succeeded(turn: 1)).0 == resting)
            #expect(F.reduce(resting, .failed(turn: 1, reason: "x")).0 == resting)
            #expect(F.reduce(resting, .dismissed(turn: 1)).0 == resting)
        }
    }

    // MARK: Cancel

    @Test func cancelFromEveryActiveStateReachesIdleAndReleasesEverything() {
        for active in allStates where active.isActive {
            let (state, effects) = F.reduce(active, .cancelRequested)
            #expect(state == .idle)
            #expect(effects == [.invalidateTurn, .releaseCapture])
        }
    }

    @Test func cancelAtRestIsANoOp() {
        for resting in [F.State.idle, .done, .failed("x")] {
            let (state, effects) = F.reduce(resting, .cancelRequested)
            #expect(state == resting)
            #expect(effects.isEmpty)
        }
    }

    @Test func lateCompletionAfterCancelIsDropped() {
        let (cancelled, _) = F.reduce(.transcribing(turn: 5, source: .file), .cancelRequested)
        #expect(F.reduce(cancelled, .succeeded(turn: 5)).0 == .idle)
        #expect(F.reduce(cancelled, .failed(turn: 5, reason: "x")).0 == .idle)
    }

    // MARK: Failure then retry

    @Test func failedStartThenRetryOpensTheMic() {
        let (failed, _) = F.reduce(.idle, .startFailed(reason: "no mic"))
        let (retry, _) = F.reduce(failed, .micOpened(turn: 2))
        #expect(retry == .listening(turn: 2))
    }

    @Test func failedFileThenNewFileRuns() {
        let (failed, _) = F.reduce(.transcribing(turn: 1, source: .file), .failed(turn: 1, reason: "x"))
        let (retry, effects) = F.reduce(failed, .fileRequested(turn: 2))
        #expect(retry == .transcribing(turn: 2, source: .file))
        #expect(effects.isEmpty)
    }

    @Test func canStartJobOnlyAtRest() {
        #expect(allStates.filter(\.canStartJob) == [.idle, .done, .failed("x")])
    }
}
