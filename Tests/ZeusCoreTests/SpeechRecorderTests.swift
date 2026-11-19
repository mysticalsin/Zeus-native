import Testing
import ZeusCore

@Suite("Speech recorder phases")
struct SpeechRecorderTests {
    private typealias S = SpeechRecorder

    private func run(_ events: [S.Event], from start: S.State = .idle) -> (state: S.State, effects: [[S.Effect]]) {
        var state = start
        var all: [[S.Effect]] = []
        for event in events {
            let (next, effects) = S.reduce(state, event)
            state = next
            all.append(effects)
        }
        return (state, all)
    }

    @Test func aTurnStartsRecordingWithNoErrors() {
        let (state, effects) = S.reduce(.idle, .started(session: 1))
        #expect(state == .recording(session: 1, errors: 0))
        #expect(effects.isEmpty)
        #expect(!state.isStopping)
    }

    @Test func aPauseWhileTheKeyIsHeldOpensAFreshRequestInsteadOfEndingTheTurn() {
        // "Meet me at three, no, four pm.": Apple ends the utterance mid-hold.
        let (state, effects) = run([.started(session: 1), .utteranceEnded(session: 1), .taskInstalled(session: 1)])
        #expect(effects[1] == [.restart])
        #expect(state == .recording(session: 1, errors: 0))
    }

    @Test func aFinalResultAfterReleaseEndsTheTurn() {
        let (state, effects) = run([.started(session: 1), .stopRequested(session: 1), .utteranceEnded(session: 1)])
        #expect(effects[2] == [.finishTurn])
        #expect(state == .stopping(session: 1))
    }

    @Test func errorsRestartUpToTheBoundThenTheTurnEnds() {
        var events: [S.Event] = [.started(session: 1)]
        for _ in 0..<3 { events += [.recognitionFailed(session: 1, maxRestarts: 3), .taskInstalled(session: 1)] }
        events.append(.recognitionFailed(session: 1, maxRestarts: 3))
        let (state, effects) = run(events)
        #expect(effects[1] == [.restart] && effects[3] == [.restart] && effects[5] == [.restart])
        #expect(effects[7] == [.finishTurn], "the fourth error in a row ends the turn")
        #expect(state == .recording(session: 1, errors: 3))
    }

    @Test func aResultBetweenErrorsResetsTheCount() {
        let (state, _) = run([
            .started(session: 1),
            .recognitionFailed(session: 1, maxRestarts: 3), .taskInstalled(session: 1),
            .recognitionFailed(session: 1, maxRestarts: 3), .taskInstalled(session: 1),
            .resultArrived(session: 1),
        ])
        #expect(state == .recording(session: 1, errors: 0))
    }

    @Test func anErrorAfterReleaseEndsTheTurnWithoutRestarting() {
        let (_, effects) = run([.started(session: 1), .stopRequested(session: 1), .recognitionFailed(session: 1, maxRestarts: 3)])
        #expect(effects[2] == [.finishTurn])
    }

    @Test func eventsFromAnOlderSessionNeverTouchTheNewTurn() {
        let live: S.State = .recording(session: 2, errors: 1)
        let stale: [S.Event] = [.utteranceEnded(session: 1), .recognitionFailed(session: 1, maxRestarts: 3),
                                .resultArrived(session: 1), .taskInstalled(session: 1)]
        for event in stale {
            let (state, effects) = S.reduce(live, event)
            #expect(state == live)
            #expect(effects.isEmpty)
        }
    }

    @Test func aStaleFinalCannotEndTheNewTurnEvenWhenTheOldOneWasStopping() {
        let (state, effects) = S.reduce(.recording(session: 2, errors: 0), .utteranceEnded(session: 1))
        #expect(state == .recording(session: 2, errors: 0))
        #expect(effects.isEmpty)
    }

    @Test func aNewTurnAfterAStopStartsClean() {
        let (state, _) = run([.stopRequested(session: 1), .started(session: 2)], from: .recording(session: 1, errors: 2))
        #expect(state == .recording(session: 2, errors: 0))
    }

    @Test func stopDuringARestartWinsAndTheInstalledTaskDoesNotRevive() {
        let (state, effects) = run([
            .started(session: 1), .utteranceEnded(session: 1),
            .stopRequested(session: 1),
            .taskInstalled(session: 1),
            .utteranceEnded(session: 1),
        ])
        #expect(state == .stopping(session: 1))
        #expect(effects[4] == [.finishTurn])
    }

    @Test func aSecondFinalDuringARestartDoesNotOpenAnotherTask() {
        let (state, effects) = run([.started(session: 1), .utteranceEnded(session: 1), .utteranceEnded(session: 1)])
        #expect(effects[2].isEmpty)
        #expect(state == .restarting(session: 1, errors: 0))
    }

    @Test func cancelBeforeAnyTurnStillBlocksAudio() {
        let (state, _) = S.reduce(.idle, .stopRequested(session: 0))
        #expect(state.isStopping)
    }
}
