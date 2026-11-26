import Foundation
import Testing
@testable import ZeusCore

@Suite("Output list") struct OutputListTests {
    private func route(
        _ uid: String, _ name: String, current: Bool = false, symbol: String = "speaker.wave.2", objectID: UInt32 = 1
    ) -> OutputList.Route {
        OutputList.Route(uid: uid, objectID: objectID, name: name, symbol: symbol, isCurrent: current)
    }

    private func opened(_ routes: [OutputList.Route]) -> OutputList.State {
        let (listening, _) = OutputList.reduce(.closed(run: 0), .toggled)
        guard case .open(let open) = listening, let token = open.reading else {
            preconditionFailure("open did not start a read")
        }
        return OutputList.reduce(listening, .facts(token: token, routes: routes)).0
    }

    private func picked(_ routes: [OutputList.Route], _ uid: String) -> OutputList.State {
        OutputList.reduce(opened(routes), .picked(uid)).0
    }

    private func openValue(_ state: OutputList.State) -> OutputList.Open? {
        if case .open(let open) = state { return open }
        return nil
    }

    private func cues(_ effects: [OutputList.Effect]) -> [String] {
        effects.compactMap { if case .cue(let text) = $0 { text } else { nil } }
    }

    private func announces(_ effects: [OutputList.Effect]) -> [String] {
        effects.compactMap { if case .announce(let text) = $0 { text } else { nil } }
    }

    private func reads(_ effects: [OutputList.Effect]) -> [UInt64] {
        effects.compactMap { if case .readDevices(let token) = $0 { token } else { nil } }
    }

    @Test func openEmitsListenThenRead() {
        let (state, effects) = OutputList.reduce(.closed(run: 0), .toggled)
        let open = openValue(state)
        #expect(open?.reading == 1)
        #expect(open?.loaded == false)
        #expect(effects == [
            .startListening,
            .readDevices(token: 1),
            .expireAfter(token: 1, seconds: OutputListTiming.readDeadline),
        ])
    }

    @Test func aSecondToggleClosesAndStops() {
        let (state, effects) = OutputList.reduce(opened([route("a", "Speakers", current: true)]), .toggled)
        #expect(state == .closed(run: 1))
        #expect(effects == [.stopListening])
    }

    @Test func aPickWritesAndShowsSwitchingWithoutMovingTheMark() {
        let routes = [route("a", "Speakers", current: true, objectID: 1), route("b", "Headphones", objectID: 2)]
        let (state, effects) = OutputList.reduce(opened(routes), .picked("b"))
        let open = openValue(state)
        #expect(open?.pending?.uid == "b")
        #expect(open?.pending?.step == .writing)
        #expect(open?.routes.map(\.isCurrent) == [true, false])
        #expect(open?.routes.map(\.uid) == ["a", "b"])
        #expect(OutputList.rows(state).map(\.status) == [.current, .switching])
        #expect(effects == [
            .write(token: 2, uid: "b"),
            .expireAfter(token: 2, seconds: OutputListTiming.writeDeadline),
        ])
    }

    @Test func aSecondPickDropsTheFirst() {
        let routes = [
            route("a", "Speakers", current: true, objectID: 1),
            route("b", "Headphones", objectID: 2),
            route("c", "Display", symbol: "display", objectID: 3),
        ]
        let first = picked(routes, "b")
        let token = openValue(first)?.pending?.token
        let (state, effects) = OutputList.reduce(first, .picked("c"))
        #expect(token == 2)
        #expect(openValue(state)?.pending?.uid == "c")
        #expect(openValue(state)?.pending?.token == 3)
        #expect(effects == [
            .write(token: 3, uid: "c"),
            .expireAfter(token: 3, seconds: OutputListTiming.writeDeadline),
        ])
        let (late, lateEffects) = OutputList.reduce(state, .writeFinished(token: 2, status: 0))
        #expect(late == state)
        #expect(lateEffects.isEmpty)
        #expect(OutputList.rows(state).map(\.status) == [.current, .none, .switching])
    }

    @Test func theCurrentRowClearsAFailureAndAnUnknownRowDoesNothing() {
        let routes = [route("a", "Speakers", current: true), route("b", "Headphones")]
        var state = picked(routes, "b")
        state = OutputList.reduce(state, .writeFinished(token: 2, status: -1)).0
        #expect(openValue(state)?.failure?.reason == .refused(-1))
        let (cleared, clearEffects) = OutputList.reduce(state, .picked("a"))
        #expect(clearEffects.isEmpty)
        #expect(openValue(cleared)?.failure == nil)
        #expect(openValue(cleared)?.pending == nil)
        let (unknown, unknownEffects) = OutputList.reduce(cleared, .picked("missing"))
        #expect(unknown == cleared)
        #expect(unknownEffects.isEmpty)
    }

    @Test func twoMatchingReadBacksLeaveNoPending() {
        let routes = [route("a", "Speakers", current: true, objectID: 1), route("b", "Headphones", objectID: 2)]
        var state = picked(routes, "b")
        let (wrote, writeEffects) = OutputList.reduce(state, .writeFinished(token: 2, status: 0))
        #expect(writeEffects == [.readBackAfter(token: 2, seconds: OutputListTiming.firstReadBack)])
        #expect(openValue(wrote)?.pending?.step == .firstCheck)
        let (first, firstEffects) = OutputList.reduce(wrote, .readBack(token: 2, uid: "b", name: "Headphones"))
        #expect(firstEffects == [
            .announce(OutputListText.soundIsOn("Headphones")),
            .readBackAfter(token: 2, seconds: OutputListTiming.secondReadBack),
        ])
        #expect(openValue(first)?.routes.map(\.uid) == ["a", "b"])
        #expect(openValue(first)?.routes.map(\.isCurrent) == [false, true])
        #expect(OutputList.rows(first).map(\.status) == [.none, .current])
        let (second, secondEffects) = OutputList.reduce(first, .readBack(token: 2, uid: "b", name: "Headphones"))
        #expect(secondEffects.isEmpty)
        #expect(openValue(second)?.pending == nil)
        #expect(openValue(second)?.failure == nil)
        #expect(openValue(second)?.routes.map(\.isCurrent) == [false, true])
        state = second
        #expect(openValue(state)?.loaded == true)
    }

    @Test func aRefusedWriteFailsWithNoReadBack() {
        let state = picked([route("a", "Speakers", current: true), route("b", "Headphones")], "b")
        let (failed, effects) = OutputList.reduce(state, .writeFinished(token: 2, status: -50))
        #expect(openValue(failed)?.failure == OutputList.Failure(uid: "b", name: "Headphones", reason: .refused(-50)))
        #expect(openValue(failed)?.pending == nil)
        #expect(effects == [.announce(OutputListText.couldNotSwitch(to: "Headphones"))])
        #expect(OutputList.rows(failed).map(\.status) == [.current, .failed])
        #expect(OutputList.rows(failed)[1].status.word == "Not switched")
        #expect(OutputList.rows(failed)[1].status.symbol == "exclamationmark.triangle")
    }

    @Test func aNilWriteIsGoneAndAsksForAFreshRead() {
        let state = picked([route("a", "Speakers", current: true), route("b", "Headphones")], "b")
        let (failed, effects) = OutputList.reduce(state, .writeFinished(token: 2, status: nil))
        #expect(openValue(failed)?.failure?.reason == .deviceGone)
        #expect(openValue(failed)?.pending == nil)
        #expect(announces(effects) == [OutputListText.couldNotSwitch(to: "Headphones")])
        #expect(reads(effects) == [3])
        #expect(effects.contains(.expireAfter(token: 3, seconds: OutputListTiming.readDeadline)))
    }

    @Test func expireWhileWritingTimesOutAndALateWriteChangesNothing() {
        let state = picked([route("a", "Speakers", current: true), route("b", "Headphones")], "b")
        let (failed, effects) = OutputList.reduce(state, .expired(2))
        #expect(openValue(failed)?.failure?.reason == .timedOut)
        #expect(openValue(failed)?.pending == nil)
        #expect(effects == [.announce(OutputListText.couldNotSwitch(to: "Headphones"))])
        let (late, lateEffects) = OutputList.reduce(failed, .writeFinished(token: 2, status: 0))
        #expect(late == failed)
        #expect(lateEffects.isEmpty)
    }

    @Test func aFirstReadBackElsewhereNeverMarksThePick() {
        let routes = [route("a", "Speakers", current: true, objectID: 1), route("b", "Headphones", objectID: 2)]
        var state = picked(routes, "b")
        state = OutputList.reduce(state, .writeFinished(token: 2, status: 0)).0
        let (failed, effects) = OutputList.reduce(state, .readBack(token: 2, uid: "a", name: "Speakers"))
        #expect(openValue(failed)?.failure?.reason == .elsewhere)
        #expect(openValue(failed)?.pending == nil)
        #expect(openValue(failed)?.routes.map(\.isCurrent) == [true, false])
        #expect(effects == [.announce(OutputListText.couldNotSwitch(to: "Headphones"))])
        #expect(OutputList.rows(failed).map(\.status) == [.current, .failed])
    }

    @Test func aNilFirstReadBackRetriesOnceThenUnread() {
        var state = picked([route("a", "Speakers", current: true), route("b", "Headphones")], "b")
        state = OutputList.reduce(state, .writeFinished(token: 2, status: 0)).0
        let (retry, retryEffects) = OutputList.reduce(state, .readBack(token: 2, uid: nil, name: nil))
        #expect(openValue(retry)?.pending?.retried == true)
        #expect(openValue(retry)?.pending?.step == .firstCheck)
        #expect(openValue(retry)?.failure == nil)
        #expect(retryEffects == [.readBackAfter(token: 2, seconds: OutputListTiming.nilRetry)])
        let (failed, effects) = OutputList.reduce(retry, .readBack(token: 2, uid: nil, name: nil))
        #expect(openValue(failed)?.failure?.reason == .unread)
        #expect(openValue(failed)?.pending == nil)
        #expect(effects == [.announce(OutputListText.couldNotSwitch(to: "Headphones"))])
    }

    @Test func aNilRetryCanStillSucceed() {
        var state = picked([route("a", "Speakers", current: true), route("b", "Headphones")], "b")
        state = OutputList.reduce(state, .writeFinished(token: 2, status: 0)).0
        state = OutputList.reduce(state, .readBack(token: 2, uid: nil, name: nil)).0
        let (checked, effects) = OutputList.reduce(state, .readBack(token: 2, uid: "b", name: "Headphones"))
        #expect(openValue(checked)?.pending?.step == .secondCheck)
        #expect(openValue(checked)?.failure == nil)
        #expect(announces(effects) == [OutputListText.soundIsOn("Headphones")])
    }

    @Test func aSecondReadBackElsewhereIsLeftWithThatName() {
        let routes = [route("a", "Speakers", current: true, objectID: 1), route("b", "Headphones", objectID: 2)]
        var state = picked(routes, "b")
        state = OutputList.reduce(state, .writeFinished(token: 2, status: 0)).0
        state = OutputList.reduce(state, .readBack(token: 2, uid: "b", name: "Headphones")).0
        let (failed, effects) = OutputList.reduce(state, .readBack(token: 2, uid: "a", name: "Speakers"))
        #expect(openValue(failed)?.failure?.reason == .left(current: "Speakers"))
        #expect(openValue(failed)?.routes.map(\.isCurrent) == [true, false])
        #expect(effects == [.announce(OutputListText.soundMoved(to: "Speakers"))])
        #expect(OutputList.rows(failed).map(\.status) == [.current, .left])
        #expect(OutputList.rows(failed)[1].status.word == "Did not stay")
    }

    @Test func aSecondReadBackWithNoNameSaysTheSoundLeft() {
        var state = picked([route("a", "Speakers", current: true), route("b", "Headphones")], "b")
        state = OutputList.reduce(state, .writeFinished(token: 2, status: 0)).0
        state = OutputList.reduce(state, .readBack(token: 2, uid: "b", name: "Headphones")).0
        let (failed, effects) = OutputList.reduce(state, .readBack(token: 2, uid: "a", name: "  "))
        #expect(openValue(failed)?.failure?.reason == .left(current: nil))
        #expect(effects == [.announce(OutputListText.soundLeft("Headphones"))])
    }

    @Test func aNilSecondReadBackLeavesTheFirstCheck() {
        var state = picked([route("a", "Speakers", current: true), route("b", "Headphones")], "b")
        state = OutputList.reduce(state, .writeFinished(token: 2, status: 0)).0
        state = OutputList.reduce(state, .readBack(token: 2, uid: "b", name: "Headphones")).0
        let (done, effects) = OutputList.reduce(state, .readBack(token: 2, uid: nil, name: nil))
        #expect(effects.isEmpty)
        #expect(openValue(done)?.pending == nil)
        #expect(openValue(done)?.failure == nil)
        #expect(openValue(done)?.routes.map(\.isCurrent) == [false, true])
    }

    @Test func aFailedRouteThatBecomesCurrentLosesItsFailure() {
        var state = picked([route("a", "Speakers", current: true), route("b", "Headphones")], "b")
        state = OutputList.reduce(state, .writeFinished(token: 2, status: -1)).0
        let (changed, changeEffects) = OutputList.reduce(state, .devicesChanged)
        #expect(changeEffects.count == 2)
        let token = reads(changeEffects)[0]
        let routes = [route("a", "Speakers"), route("b", "Headphones", current: true)]
        let (cleared, effects) = OutputList.reduce(changed, .facts(token: token, routes: routes))
        #expect(effects.isEmpty)
        #expect(openValue(cleared)?.failure == nil)
        #expect(OutputList.rows(cleared).map(\.status) == [.none, .current])
    }

    @Test func factsDuringASwitchDoNotMoveTheMark() {
        let routes = [route("a", "Speakers", current: true, objectID: 1), route("b", "Headphones", objectID: 2)]
        var state = picked(routes, "b")
        let (changed, changeEffects) = OutputList.reduce(state, .devicesChanged)
        let token = reads(changeEffects)[0]
        let moved = [route("a", "Speakers", objectID: 1), route("b", "Headphones", current: true, objectID: 2)]
        let (held, _) = OutputList.reduce(changed, .facts(token: token, routes: moved))
        #expect(openValue(held)?.routes.map(\.isCurrent) == [true, false])
        #expect(openValue(held)?.routes.map(\.uid) == ["a", "b"])
        #expect(OutputList.rows(held).map(\.status) == [.current, .switching])
        state = held
        #expect(openValue(state)?.pending?.uid == "b")
    }

    @Test func oneHundredChangesDuringAReadGiveOneMoreRead() {
        let (listening, _) = OutputList.reduce(.closed(run: 0), .toggled)
        var state = listening
        for _ in 0..<100 {
            let (next, effects) = OutputList.reduce(state, .devicesChanged)
            #expect(reads(effects).isEmpty)
            state = next
        }
        #expect(openValue(state)?.readQueued == true)
        let (loaded, effects) = OutputList.reduce(state, .facts(token: 1, routes: [route("a", "Speakers", current: true)]))
        #expect(reads(effects) == [2])
        #expect(openValue(loaded)?.readQueued == false)
        #expect(openValue(loaded)?.reading == 2)
        let (idle, idleEffects) = OutputList.reduce(loaded, .expired(2))
        #expect(reads(idleEffects).isEmpty)
        #expect(openValue(idle)?.reading == nil)
        #expect(openValue(idle)?.routes.map(\.uid) == ["a"])
    }

    @Test func changesWhileClosedOrSettlingEmitNothing() {
        let closed = OutputList.reduce(.closed(run: 4), .devicesChanged)
        #expect(closed.0 == .closed(run: 4))
        #expect(closed.1.isEmpty)
        let settling = OutputList.reduce(picked([route("a", "Speakers", current: true), route("b", "Headphones")], "b"), .closed)
        #expect(settling.1 == [.stopListening])
        let ignored = OutputList.reduce(settling.0, .devicesChanged)
        #expect(ignored.0 == settling.0)
        #expect(ignored.1.isEmpty)
        let again = OutputList.reduce(settling.0, .closed)
        #expect(again.0 == settling.0)
        #expect(again.1 == [.stopListening])
    }

    @Test func expireDuringAReadContinuesOnlyWhenAChangeWasQueued() {
        let (listening, _) = OutputList.reduce(.closed(run: 0), .toggled)
        let (quiet, quietEffects) = OutputList.reduce(listening, .expired(1))
        #expect(quietEffects.isEmpty)
        #expect(openValue(quiet)?.reading == nil)
        var queued = listening
        queued = OutputList.reduce(queued, .devicesChanged).0
        let (again, effects) = OutputList.reduce(queued, .expired(1))
        #expect(reads(effects) == [2])
        #expect(openValue(again)?.reading == 2)
    }

    @Test func aPendingDeviceMissingFromFactsFails() {
        let routes = [route("a", "Speakers", current: true), route("b", "Headphones")]
        var state = picked(routes, "b")
        let (changed, changeEffects) = OutputList.reduce(state, .devicesChanged)
        let token = reads(changeEffects)[0]
        let (failed, effects) = OutputList.reduce(changed, .facts(token: token, routes: [route("a", "Speakers", current: true)]))
        #expect(openValue(failed)?.failure == OutputList.Failure(uid: "b", name: "Headphones", reason: .deviceGone))
        #expect(openValue(failed)?.pending == nil)
        #expect(effects == [.announce(OutputListText.couldNotSwitch(to: "Headphones"))])
        state = failed
        #expect(OutputList.rows(state).map(\.route.uid) == ["a"])
    }

    @Test func aStaleFactsTokenIsDropped() {
        let (listening, _) = OutputList.reduce(.closed(run: 0), .toggled)
        let (same, effects) = OutputList.reduce(listening, .facts(token: 9, routes: [route("a", "Speakers", current: true)]))
        #expect(same == listening)
        #expect(effects.isEmpty)
    }

    @Test func closingMidSwitchThenAFailureCuesOnce() {
        let state = picked([route("a", "Speakers", current: true), route("b", "Headphones")], "b")
        let (settling, stopped) = OutputList.reduce(state, .closed)
        #expect(stopped == [.stopListening])
        if case .settling(let pending, _) = settling {
            #expect(pending.uid == "b")
            #expect(pending.step == .writing)
        } else {
            Issue.record("expected settling")
        }
        let (closed, effects) = OutputList.reduce(settling, .writeFinished(token: 2, status: -1))
        #expect(closed == .closed(run: 2))
        #expect(cues(effects) == [OutputListText.couldNotSwitch(to: "Headphones")])
        #expect(announces(effects) == [OutputListText.couldNotSwitch(to: "Headphones")])
        let (late, lateEffects) = OutputList.reduce(closed, .writeFinished(token: 2, status: 0))
        #expect(late == closed)
        #expect(lateEffects.isEmpty)
    }

    @Test func closingMidSwitchThenSuccessCuesNone() {
        let started = picked([route("a", "Speakers", current: true), route("b", "Headphones")], "b")
        let settling = OutputList.reduce(started, .closed).0
        var state = OutputList.reduce(settling, .writeFinished(token: 2, status: 0)).0
        let (first, firstEffects) = OutputList.reduce(state, .readBack(token: 2, uid: "b", name: "Headphones"))
        #expect(cues(firstEffects).isEmpty)
        #expect(announces(firstEffects) == [OutputListText.soundIsOn("Headphones")])
        state = first
        let (done, effects) = OutputList.reduce(state, .readBack(token: 2, uid: "b", name: "Headphones"))
        #expect(done == .closed(run: 2))
        #expect(effects.isEmpty)
        #expect(cues(effects).isEmpty)
    }

    @Test func reopeningWhileSettlingShowsTheResultWithoutACue() {
        let state = picked([route("a", "Speakers", current: true), route("b", "Headphones")], "b")
        let settling = OutputList.reduce(state, .closed).0
        let (reopened, effects) = OutputList.reduce(settling, .toggled)
        #expect(effects.first == .startListening)
        #expect(openValue(reopened)?.pending?.uid == "b")
        #expect(openValue(reopened)?.pending?.token == 2)
        #expect(reads(effects).count == 1)
        let (failed, failedEffects) = OutputList.reduce(reopened, .writeFinished(token: 2, status: -1))
        #expect(cues(failedEffects).isEmpty)
        #expect(announces(failedEffects) == [OutputListText.couldNotSwitch(to: "Headphones")])
        #expect(openValue(failed)?.failure?.reason == .refused(-1))
    }

    @Test func interruptedDropsLaterAnswersAndDoesNotCue() {
        let open = picked([route("a", "Speakers", current: true), route("b", "Headphones")], "b")
        let (fromOpen, openEffects) = OutputList.reduce(open, .interrupted)
        #expect(fromOpen == .closed(run: 3))
        #expect(openEffects == [.stopListening])
        #expect(cues(openEffects).isEmpty)
        let (late, lateEffects) = OutputList.reduce(fromOpen, .writeFinished(token: 2, status: -1))
        #expect(late == fromOpen)
        #expect(lateEffects.isEmpty)

        let settling = OutputList.reduce(open, .closed).0
        let (fromSettling, settlingEffects) = OutputList.reduce(settling, .interrupted)
        #expect(fromSettling == .closed(run: 3))
        #expect(settlingEffects.isEmpty)
        let (after, afterEffects) = OutputList.reduce(fromSettling, .readBack(token: 2, uid: "a", name: "Speakers"))
        #expect(after == fromSettling)
        #expect(afterEffects.isEmpty)
        #expect(cues(afterEffects).isEmpty)
    }

    @Test func closedAlwaysStopsListening() {
        let idle = OutputList.reduce(.closed(run: 0), .closed)
        #expect(idle.0 == .closed(run: 0))
        #expect(idle.1 == [.stopListening])
        let open = opened([route("a", "Speakers", current: true)])
        let (shut, effects) = OutputList.reduce(open, .closed)
        #expect(shut == .closed(run: 1))
        #expect(effects == [.stopListening])
    }

    @Test func wordsAndSentencesHaveNoDash() {
        let words = [
            OutputRowStatus.current.word, OutputRowStatus.switching.word, OutputRowStatus.failed.word,
            OutputRowStatus.left.word, OutputRowStatus.none.word,
            OutputRowStatus.current.symbol, OutputRowStatus.switching.symbol, OutputRowStatus.failed.symbol,
            OutputRowStatus.left.symbol,
            OutputListText.couldNotSwitch(to: "Headphones"),
            OutputListText.soundMoved(to: "Speakers"),
            OutputListText.soundIsOn("Headphones"),
            OutputListText.soundLeft("Headphones"),
        ]
        for word in words {
            #expect(!word.contains("\u{2014}"))
            #expect(!word.contains("\u{2013}"))
        }
    }

    @Test func snapshotSampleHasFiveRoutesOneCurrentOneFailed() {
        let rows = OutputList.rows(.snapshotSample)
        #expect(rows.count == 5)
        #expect(rows.filter { $0.status == .current }.count == 1)
        #expect(rows.filter { $0.status == .failed }.map(\.route.uid) == ["desk"])
        #expect(rows.map(\.symbol) == rows.map(\.route.symbol))
    }

    @Test @MainActor func aFakeConforms() {
        let fake = OutputListFake()
        let controlling: any OutputListControlling = fake
        #expect(controlling.state == .closed(run: 0))
        controlling.toggle()
        #expect(fake.toggles == 1)
    }
}

@MainActor
private final class OutputListFake: OutputListControlling {
    var state: OutputList.State = .closed(run: 0)
    private(set) var toggles = 0
    func toggle() { toggles += 1 }
    func close() {}
    func pick(uid: String) {}
}
