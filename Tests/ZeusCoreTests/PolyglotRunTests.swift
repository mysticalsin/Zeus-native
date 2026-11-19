import Testing
import ZeusCore

@Suite("Polyglot run")
struct PolyglotRunTests {
    private typealias R = PolyglotRun

    private func run(_ events: [R.Event], from start: R.State = .idle) -> (state: R.State, effects: [[R.Effect]]) {
        var state = start
        var all: [[R.Effect]] = []
        for event in events {
            let (next, effects) = R.reduce(state, event)
            state = next
            all.append(effects)
        }
        return (state, all)
    }

    private func starting(_ token: Int, opened: Set<R.Input> = [], ended: Set<R.Input> = [], notes: [String] = []) -> R.State {
        .starting(token: token, opened: opened, ended: ended, notes: notes)
    }

    // MARK: Happy path

    @Test func startOpensInputsAndBeginsListening() {
        let (state, effects) = run([
            .startRequested(token: 1),
            .inputOpened(token: 1, input: .microphone),
            .inputOpened(token: 1, input: .system),
            .startSettled(token: 1),
        ])
        #expect(state == .listening(token: 1, open: [.microphone, .system]))
        #expect(effects[3] == [.began(notes: [])])
        #expect(state.isListening && !state.isStarting && state.isActive)
    }

    @Test func stopThenDrainReturnsToIdle() {
        let (state, _) = run([.stopRequested(token: 2), .drained(token: 2)], from: .listening(token: 1, open: [.microphone]))
        #expect(state == .idle)
    }

    // MARK: Stop during start

    @Test func stopDuringStartMakesLateInputsReleaseThemselves() {
        let (state, effects) = run([
            .startRequested(token: 1),
            .stopRequested(token: 2),
            .inputOpened(token: 1, input: .microphone),
            .startSettled(token: 1),
        ])
        #expect(state == .stopping(token: 2))
        #expect(effects[2] == [.release(.microphone)], "a capture that opens after Stop must be stopped")
        #expect(effects[3] == [.discarded])
        #expect(!state.isActive)
    }

    @Test func stopThenQuickStartKeepsTheNewRunAndIgnoresTheOldRunsLateEvents() {
        let (state, effects) = run([
            .startRequested(token: 1),
            .stopRequested(token: 2),
            .startRequested(token: 3),
            .inputOpened(token: 1, input: .microphone),   // the first run's capture opens late
            .startSettled(token: 1),                        // and settles late
            .inputOpened(token: 3, input: .microphone),
            .startSettled(token: 3),
        ])
        #expect(effects[2].isEmpty)
        #expect(effects[3] == [.release(.microphone)])
        #expect(effects[4] == [.discarded])
        #expect(state == .listening(token: 3, open: [.microphone]))
        #expect(effects[6] == [.began(notes: [])])
    }

    @Test func aDrainFromAnOlderStopCannotEndANewerRun() {
        let (state, _) = run([.drained(token: 2)], from: .listening(token: 3, open: [.system]))
        #expect(state == .listening(token: 3, open: [.system]))
        let (stopping, _) = run([.drained(token: 2)], from: .stopping(token: 4))
        #expect(stopping == .stopping(token: 4))
    }

    @Test func stopWhenIdleChangesNothing() {
        let (state, effects) = R.reduce(.idle, .stopRequested(token: 5))
        #expect(state == .idle)
        #expect(effects.isEmpty)
    }

    // MARK: Double start

    @Test func aSecondStartWhileStartingOrListeningIsIgnored() {
        let (a, ea) = R.reduce(starting(1), .startRequested(token: 2))
        #expect(a == starting(1))
        #expect(ea.isEmpty)
        let (b, eb) = R.reduce(.listening(token: 1, open: [.microphone]), .startRequested(token: 2))
        #expect(b == .listening(token: 1, open: [.microphone]))
        #expect(eb.isEmpty)
    }

    @Test func startIsAllowedWhileTheLastRunIsStillDraining() {
        let (state, _) = R.reduce(.stopping(token: 2), .startRequested(token: 3))
        #expect(state == starting(3))
    }

    // MARK: Errors mid-start

    @Test func engineFailureBeforeAnyInputAbortsTheStart() {
        let (state, effects) = run([.startRequested(token: 1), .startFailed(token: 1, message: "No on-device recognition.")])
        #expect(state == .idle)
        #expect(effects[1] == [.aborted(notes: ["No on-device recognition."])])
    }

    @Test func aStaleEngineFailureDoesNotTouchTheNewRun() {
        let (state, effects) = R.reduce(starting(3), .startFailed(token: 1, message: "old"))
        #expect(state == starting(3))
        #expect(effects == [.discarded])
    }

    @Test func oneInputFailingStillListensOnTheOtherWithTheProblemNoted() {
        let (state, effects) = run([
            .startRequested(token: 1),
            .inputFailed(token: 1, input: .microphone, message: "Microphone is off."),
            .inputOpened(token: 1, input: .system),
            .startSettled(token: 1),
        ])
        #expect(state == .listening(token: 1, open: [.system]))
        #expect(effects[3] == [.began(notes: ["Microphone is off."])])
    }

    @Test func everyInputFailingAbortsWithAllTheProblems() {
        let (state, effects) = run([
            .startRequested(token: 1),
            .inputFailed(token: 1, input: .microphone, message: "A"),
            .inputFailed(token: 1, input: .system, message: "B"),
            .startSettled(token: 1),
        ])
        #expect(state == .idle)
        #expect(effects[3] == [.aborted(notes: ["A", "B"])])
    }

    // MARK: Inputs ending

    @Test func anInputThatEndedBeforeItsStartFinishedIsNeverCountedAsOpen() {
        // The microphone changed while it was still opening: the run used to report "listening" on a dead mic.
        let (state, effects) = run([
            .startRequested(token: 1),
            .inputEnded(token: 1, input: .microphone, message: "The microphone changed."),
            .inputOpened(token: 1, input: .microphone),
            .startSettled(token: 1),
        ])
        #expect(effects[2] == [.release(.microphone)])
        #expect(state == .idle)
        #expect(effects[3] == [.aborted(notes: ["The microphone changed."])])
    }

    @Test func anOpenMicEndingMidStartKeepsTheRunGoingOnTheOtherInput() {
        let (state, effects) = run([
            .startRequested(token: 1),
            .inputOpened(token: 1, input: .microphone),
            .inputEnded(token: 1, input: .microphone, message: "The microphone changed."),
            .inputOpened(token: 1, input: .system),
            .startSettled(token: 1),
        ])
        #expect(effects[2] == [.release(.microphone)])
        #expect(state == .listening(token: 1, open: [.system]))
        #expect(effects[4] == [.began(notes: ["The microphone changed."])])
    }

    @Test func losingOneOfTwoInputsKeepsListening() {
        let (state, effects) = R.reduce(.listening(token: 1, open: [.microphone, .system]),
                                        .inputEnded(token: 1, input: .system, message: "Mac audio ended."))
        #expect(state == .listening(token: 1, open: [.microphone]))
        #expect(effects == [.release(.system)])
    }

    @Test func losingTheLastInputEndsTheRun() {
        let (state, effects) = R.reduce(.listening(token: 1, open: [.system]),
                                        .inputEnded(token: 1, input: .system, message: "Mac audio ended."))
        #expect(state == .listening(token: 1, open: []))
        #expect(effects == [.release(.system), .endRun])
    }

    @Test func anEndFromAnOlderRunOrAnInputThatIsNotOpenChangesNothing() {
        let live: R.State = .listening(token: 3, open: [.microphone])
        let (a, ea) = R.reduce(live, .inputEnded(token: 1, input: .microphone, message: "old"))
        #expect(a == live && ea.isEmpty)
        let (b, eb) = R.reduce(live, .inputEnded(token: 3, input: .system, message: "not open"))
        #expect(b == live && eb.isEmpty)
        let (c, ec) = R.reduce(.idle, .inputEnded(token: 3, input: .microphone, message: "idle"))
        #expect(c == .idle && ec.isEmpty)
    }
}
