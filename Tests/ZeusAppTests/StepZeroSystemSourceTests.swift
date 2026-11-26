import Testing
@testable import Zeus

@Suite("Step zero system source")
struct StepZeroSystemSourceTests {
    @Test func aChildThatReportsNothingSendsNoCommand() {
        var state = SystemSourceSection.fresh()
        let began = step(&state, .begin)
        #expect(began.contains(.ask(.read)))
        #expect(state.commands.isEmpty)
        step(&state, .fact(.nothing))
        #expect(state.attempt == .homeUserTmp)
        step(&state, .fact(.nothing))
        #expect(state.attempt == .sessionSet)
        step(&state, .fact(.nothing))
        #expect(state.itemSeen == .no)
        #expect(state.needs == .unknown)
        step(&state, .fact(.gate(.absent)))
        #expect(state.part == .exit)
        #expect(!state.enteredSymbols)
        #expect(state.commands.isEmpty)
        #expect(state.seeks.isEmpty)
        #expect(state.canaryPublished == false)
    }

    @Test func aMissOnAttemptAAndAHitOnBRecordsHomeUserTmp() {
        var state = SystemSourceSection.fresh()
        step(&state, .begin)
        #expect(state.attempt == .none)
        step(&state, .fact(.nothing))
        #expect(state.attempt == .homeUserTmp)
        #expect(state.commands.isEmpty)
        step(&state, .fact(.playing(true)))
        #expect(state.itemSeen == .yes)
        #expect(state.needs == .homeUserTmp)
        #expect(state.beganPlaying)
    }

    @Test func nextPreviousAndSeekAreNeverSentWhenTheClassIsNotPlayer() {
        var state = opened(class: .browser, elapsed: 30)
        walkToSkip(&state, keyLeavesPlaying: true)
        #expect(!state.commands.contains(SystemSourceSection.MediaCommand.next))
        #expect(!state.commands.contains(SystemSourceSection.MediaCommand.previous))
        #expect(state.seeks.isEmpty)
        #expect(state.seekAnswer == .notMeasured)
        #expect(state.nextAnswer == .notMeasured)
        #expect(state.previousAnswer == .notMeasured)
        #expect(state.part == .artwork)
        #expect(state.appClass == .browser)
    }

    @Test func nextIsNotSentBefore21Seconds() {
        var state = opened(class: .player, elapsed: 20)
        walkToSkip(&state, keyLeavesPlaying: true)
        #expect(state.part == .skip)
        #expect(!state.commands.contains(SystemSourceSection.MediaCommand.next))
        let sent = step(&state, .fact(.elapsed(21)))
        #expect(sent.contains(.journal(.next)))
        #expect(state.commands.contains(SystemSourceSection.MediaCommand.next))
        #expect(earlierThanNext(state.commands))

        var held = opened(class: .player, elapsed: 20)
        walkToSkip(&held, keyLeavesPlaying: true)
        step(&held, .waited(seconds: SystemSourceSection.skipWaitLimitSeconds))
        #expect(!held.commands.contains(SystemSourceSection.MediaCommand.next))
        #expect(held.nextAnswer == .notMeasured)
    }

    @Test func theCanaryIsNotPublishedWhileStillPlayingUnlessTheFiveSecondWaitRan() {
        var state = opened(class: .player, elapsed: 30)
        finishTransport(&state)
        step(&state, .fact(.playing(true)))
        #expect(state.canaryPublished == false)
        step(&state, .fact(.playing(true)))
        #expect(state.cursor == .awaitCanaryWindow)
        #expect(state.canaryPublished == false)
        step(&state, .waited(seconds: SystemSourceSection.pauseGiveUpSeconds))
        step(&state, .ownerDidNotPause)
        let early = step(&state, .waited(seconds: SystemSourceSection.stillPlayingSeconds - 1))
        #expect(!early.contains(.publishCanary))
        #expect(state.canaryPublished == false)
        #expect(state.precondition == nil)
        let late = step(&state, .waited(seconds: 1))
        #expect(late.contains(.publishCanary))
        #expect(state.canaryPublished)
        #expect(state.stillPlayingWaitRan)
        #expect(state.precondition == .stillPlaying)
    }

    @Test func theCanaryIsClearedOnEveryPath() {
        var published = opened(class: .player, elapsed: 30)
        finishTransport(&published)
        reachSeen(&published, stillPlaying: false)
        #expect(published.canaryCleared)
        #expect(published.canaryPublished)

        var stalled = opened(class: .player, elapsed: 30)
        finishTransport(&stalled)
        step(&stalled, .fact(.playing(false)))
        #expect(stalled.canaryPublished)
        #expect(stalled.cursor == .awaitCanarySeen)
        let timed = step(&stalled, .timedOut)
        #expect(timed.contains(.clearCanary))
        #expect(stalled.canaryCleared)
        #expect(stalled.timedOut)

        var waited = opened(class: .player, elapsed: 30)
        finishTransport(&waited)
        step(&waited, .fact(.playing(true)))
        step(&waited, .fact(.playing(true)))
        step(&waited, .waited(seconds: SystemSourceSection.pauseGiveUpSeconds))
        step(&waited, .ownerDidNotPause)
        step(&waited, .waited(seconds: SystemSourceSection.stillPlayingSeconds))
        let cleared = step(&waited, .fact(.seen(true)))
        #expect(cleared.contains(.clearCanary))
        #expect(waited.canaryCleared)
        #expect(waited.precondition == .stillPlaying)
    }

    @Test func aChangedElectedAppAsksTheOwnerAndRecordsTheRestore() {
        var state = opened(class: .player, elapsed: 30)
        finishTransport(&state)
        reachSeen(&state, stillPlaying: false)
        let asked = step(&state, .fact(.same(false)))
        #expect(asked.contains(.askOwner(.electedChanged)))
        #expect(state.canaryCleared)
        step(&state, .ownerElected(true))
        #expect(state.restoredElected == .yes)
    }

    @Test func thePlayStateEndsAsItBeganAfterTheKeyPress() {
        var state = opened(class: .player, elapsed: 30)
        finishTransport(&state)
        reachSeen(&state, stillPlaying: false)
        step(&state, .fact(.same(true)))
        #expect(state.restoredElected == .yes)
        step(&state, .ownerPressedPlay)
        let restore = step(&state, .fact(.playing(false)))
        #expect(state.beganPlaying)
        #expect(restore.contains(.journal(.play)))
        #expect(restore.contains(.ask(.command(SystemSourceSection.MediaCommand.play))))
        step(&state, .fact(.playing(true)))
        #expect(state.playing == state.beganPlaying)
        #expect(state.restoredPlay == .yes)
    }

    @Test func aChildThatNeverAnswersGivesTimedOut() {
        var state = SystemSourceSection.fresh()
        step(&state, .begin)
        let effects = step(&state, .timedOut)
        #expect(state.itemSeen == .timedOut)
        #expect(state.lineAnswer == .timedOut)
        #expect(state.timedOut)
        #expect(effects.contains(.journal(.timedOut)))
        #expect(effects.contains(.stopChild))
        #expect(state.commands.isEmpty)
        #expect(state.seeks.isEmpty)
    }

    @Test func noLineReachesAnAnswerExceptThroughTheDecoder() {
        let secret = "Secret Title"
        var calls = 0
        let rejected = SystemSourceSection.accept(line: "Playing yes") { line in
            calls += 1
            guard line.utf8.allSatisfy({ byte in
                (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 32
            }) else { return nil }
            return line == "playing yes" ? .playing(true) : nil
        }
        #expect(calls == 1)
        #expect(rejected == nil)

        var state = SystemSourceSection.fresh()
        step(&state, .begin)
        let before = state
        let ignored = SystemSourceSection.accept(line: secret) { _ in nil }
        #expect(ignored == nil)
        #expect(state == before)

        let accepted = SystemSourceSection.accept(line: "playing yes") { line in
            line == "playing yes" ? .playing(true) : nil
        }
        #expect(accepted == .playing(true))
        step(&state, .fact(accepted!))
        #expect(state.itemSeen == .yes)
        #expect(!String(describing: state).contains(secret))
        #expect(!String(reflecting: state).contains(secret))
    }

    @Test func theChildStandardErrorIsTheNullDevice() {
        #expect(SystemSourceSection.childStandardError == .nullDevice)
    }

    @Test func aPauseIsJournaledBeforeTheCommand() {
        var state = opened(class: .player, elapsed: 30)
        let effects = step(&state, .fact(.nothing))
        let journal = effects.firstIndex(of: .journal(.pause))
        let command = effects.firstIndex(of: .ask(.command(SystemSourceSection.MediaCommand.pause)))
        #expect(journal != nil)
        #expect(command != nil)
        #expect(journal! < command!)
    }
}

@discardableResult
private func step(_ state: inout SystemSourceSection.State, _ event: SystemSourceSection.Event) -> [SystemSourceSection.Effect] {
    let result = SystemSourceSection.reduce(state, event)
    state = result.state
    return result.effects
}

private func opened(class kind: SystemSourceSection.AppClass, elapsed: Int) -> SystemSourceSection.State {
    var state = SystemSourceSection.fresh()
    step(&state, .begin)
    step(&state, .fact(.appClass(kind)))
    step(&state, .fact(.elapsed(elapsed)))
    step(&state, .fact(.playing(true)))
    step(&state, .fact(.gate(.absent)))
    return state
}

private func finishTransport(_ state: inout SystemSourceSection.State) {
    step(&state, .fact(.nothing))
    #expect(state.cursor == .awaitPauseAck)
    step(&state, .fact(.playing(false)))
    step(&state, .fact(.playing(true)))
    if state.appClass == .player {
        step(&state, .fact(.yes))
        step(&state, .fact(.yes))
    }
    #expect(state.cursor == .awaitCanaryRead)
}

private func reachSeen(_ state: inout SystemSourceSection.State, stillPlaying: Bool) {
    step(&state, .fact(.playing(true)))
    if stillPlaying {
        step(&state, .fact(.playing(true)))
        step(&state, .waited(seconds: SystemSourceSection.pauseGiveUpSeconds))
        step(&state, .ownerDidNotPause)
        step(&state, .waited(seconds: SystemSourceSection.stillPlayingSeconds))
    } else {
        step(&state, .fact(.playing(false)))
    }
    step(&state, .fact(.seen(true)))
    #expect(state.canaryCleared)
}

private func walkToSkip(_ state: inout SystemSourceSection.State, keyLeavesPlaying: Bool) {
    finishTransport(&state)
    let playingAtCanary = state.beganPlaying
    step(&state, .fact(.playing(playingAtCanary)))
    if playingAtCanary {
        step(&state, .fact(.playing(false)))
    }
    step(&state, .fact(.seen(true)))
    step(&state, .fact(.same(true)))
    step(&state, .ownerPressedPlay)
    step(&state, .fact(.playing(keyLeavesPlaying)))
    if keyLeavesPlaying != state.beganPlaying {
        step(&state, .fact(.playing(state.beganPlaying)))
    }
}

private func earlierThanNext(_ commands: [Int]) -> Bool {
    guard let next = commands.firstIndex(of: SystemSourceSection.MediaCommand.next) else { return false }
    return commands[..<next].allSatisfy { $0 != SystemSourceSection.MediaCommand.next }
}
