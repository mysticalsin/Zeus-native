import Foundation
import Testing
@testable import ZeusCore

@Suite("Music wings pause hold") struct MusicWingsHoldTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func labelsAndDelays() {
        #expect(PauseCollapse(label: "At once") == .atOnce)
        #expect(PauseCollapse(label: " After 10 s ") == .after(10))
        #expect(PauseCollapse(label: "After 1 min") == .after(60))
        #expect(PauseCollapse(label: "Never") == .never)
        #expect(PauseCollapse(label: "Later") == .atOnce)
        #expect(PauseCollapse(label: "") == .atOnce)
        #expect(PauseCollapse(delay: 10) == .after(10))
        #expect(PauseCollapse(delay: 0) == .atOnce)
        #expect(PauseCollapse(delay: -3) == .atOnce)
        #expect(PauseCollapse(delay: .nan) == .atOnce)
        #expect(PauseCollapse(delay: .infinity) == .atOnce)
    }

    @Test func eachPolicyOnAPauseFromPlaying() {
        let playing = play()
        let atOnce = step(playing, .playback(.paused, wingsOnScreen: true, now: start), policy: .atOnce)
        #expect(atOnce.state == .hidden)
        #expect(atOnce.effects.isEmpty)

        let ten = step(playing, .playback(.paused, wingsOnScreen: true, now: start), policy: .after(10))
        #expect(ten.state == .held(since: start, until: start.addingTimeInterval(10)))
        #expect(ten.effects == [.wake(at: start.addingTimeInterval(10))])

        let minute = step(playing, .playback(.paused, wingsOnScreen: true, now: start), policy: .after(60))
        #expect(minute.state == .held(since: start, until: start.addingTimeInterval(60)))

        let forever = step(playing, .playback(.paused, wingsOnScreen: true, now: start), policy: .never)
        #expect(forever.state == .held(since: start, until: nil))
        #expect(forever.effects.isEmpty)

        let broken = step(playing, .playback(.paused, wingsOnScreen: true, now: start), policy: .after(.nan))
        #expect(broken.state == .hidden)
        #expect(broken.effects.isEmpty)
    }

    @Test func firstSeenPausedStaysHidden() {
        let paused = step(.hidden, .playback(.paused, wingsOnScreen: true, now: start), policy: .after(10))
        #expect(paused.state == .hidden)
        #expect(paused.effects.isEmpty)
        #expect(MusicWingsHold.showsWings(.hidden) == false)
        #expect(MusicWingsHold.isPaused(.hidden) == false)
    }

    @Test func aPauseWithTheWingsOffScreenStaysHiddenUnderEveryPolicy() {
        let playing = play()
        for policy in [PauseCollapse.atOnce, .after(10), .never] {
            let paused = step(playing, .playback(.paused, wingsOnScreen: false, now: start), policy: policy)
            #expect(paused.state == .hidden)
            #expect(paused.effects.isEmpty)
            let again = step(paused.state, .playback(.playing, wingsOnScreen: true, now: later(1)), policy: policy)
            #expect(again.state == .playing)
            #expect(again.effects.isEmpty)
        }
    }

    @Test func theSwitchGoingOffDuringAHoldHidesAndComingBackDoesNotRestoreIt() {
        let held = hold(for: 30)
        let off = step(held.state, .wingsSwitchedOff, policy: .after(30))
        #expect(off.state == .hidden)
        #expect(off.effects == [.cancelWake])
        let still = step(off.state, .playback(.paused, wingsOnScreen: true, now: later(2)), policy: .after(30))
        #expect(still.state == .hidden)
        #expect(still.effects.isEmpty)
        let policy = step(still.state, .policy(.never, now: later(3)), policy: .after(30))
        #expect(policy.state == .hidden)
        #expect(policy.effects.isEmpty)
    }

    @Test func playDuringAHoldKeepsTheWingsAndGoneHidesThem() {
        let held = hold(for: 30)
        #expect(MusicWingsHold.showsWings(held.state))
        #expect(MusicWingsHold.isPaused(held.state))
        let playing = step(held.state, .playback(.playing, wingsOnScreen: true, now: later(4)), policy: .after(30))
        #expect(playing.state == .playing)
        #expect(playing.effects == [.cancelWake])
        #expect(MusicWingsHold.showsWings(playing.state))
        #expect(MusicWingsHold.isPaused(playing.state) == false)

        let quit = step(held.state, .playback(.none, wingsOnScreen: true, now: later(4)), policy: .after(30))
        #expect(quit.state == .hidden)
        #expect(quit.effects == [.cancelWake])
    }

    @Test func aSecondPauseKeepsSince() {
        let held = hold(for: 30)
        let again = step(held.state, .playback(.paused, wingsOnScreen: false, now: later(5)), policy: .after(10))
        #expect(again.state == .held(since: start, until: start.addingTimeInterval(30)))
        #expect(again.effects.isEmpty)
    }

    @Test func deadlinesBeforeAtAndAfterTheEnd() {
        let held = hold(for: 10)
        let early = step(held.state, .deadline(now: later(9)), policy: .after(10))
        #expect(early.state == held.state)
        #expect(early.effects == [.wake(at: start.addingTimeInterval(10))])

        let exact = step(held.state, .deadline(now: later(10)), policy: .after(10))
        #expect(exact.state == .hidden)
        #expect(exact.effects == [.cancelWake])

        let late = step(held.state, .deadline(now: later(11)), policy: .after(10))
        #expect(late.state == .hidden)
        #expect(late.effects == [.cancelWake])

        let forever = step(play(), .playback(.paused, wingsOnScreen: true, now: start), policy: .never)
        let ignored = step(forever.state, .deadline(now: later(10_000)), policy: .never)
        #expect(ignored.state == forever.state)
        #expect(ignored.effects.isEmpty)
    }

    @Test func aPolicyChangeDuringAHoldRetimesFromThePause() {
        let held = hold(for: 60)
        let shorter = step(held.state, .policy(.after(10), now: later(5)), policy: .after(60))
        #expect(shorter.state == .held(since: start, until: start.addingTimeInterval(10)))
        #expect(shorter.effects == [.cancelWake, .wake(at: start.addingTimeInterval(10))])

        let alreadyPast = step(held.state, .policy(.after(10), now: later(15)), policy: .after(60))
        #expect(alreadyPast.state == .hidden)
        #expect(alreadyPast.effects == [.cancelWake])

        let forever = step(held.state, .policy(.never, now: later(5)), policy: .after(60))
        #expect(forever.state == .held(since: start, until: nil))
        #expect(forever.effects == [.cancelWake])

        let immediate = step(held.state, .policy(.atOnce, now: later(5)), policy: .after(60))
        #expect(immediate.state == .hidden)
        #expect(immediate.effects == [.cancelWake])

        let whileHidden = step(.hidden, .policy(.after(10), now: start), policy: .atOnce)
        #expect(whileHidden.state == .hidden)
        #expect(whileHidden.effects.isEmpty)

        let whilePlaying = step(play(), .policy(.never, now: start), policy: .atOnce)
        #expect(whilePlaying.state == .playing)
        #expect(whilePlaying.effects.isEmpty)
    }

    @Test func aClockSetBackBeforeThePauseCollapses() {
        let held = hold(for: 30)
        let before = start.addingTimeInterval(-1)
        let deadline = step(held.state, .deadline(now: before), policy: .after(30))
        #expect(deadline.state == .hidden)
        #expect(deadline.effects == [.cancelWake])
        let policy = step(held.state, .policy(.after(60), now: before), policy: .after(30))
        #expect(policy.state == .hidden)
        let paused = step(held.state, .playback(.paused, wingsOnScreen: true, now: before), policy: .after(30))
        #expect(paused.state == .hidden)
    }

    @Test func aThousandEdgesLeaveAtMostOneWake() {
        var state = play()
        var wakes: [Date] = []
        for index in 0..<1000 {
            let now = start.addingTimeInterval(Double(index))
            let event: MusicWingsHold.Event = index.isMultiple(of: 2)
                ? .playback(.paused, wingsOnScreen: true, now: now)
                : .playback(.playing, wingsOnScreen: true, now: now)
            let next = step(state, event, policy: .after(10))
            state = next.state
            for effect in next.effects {
                switch effect {
                case .wake(let at): wakes.append(at)
                case .cancelWake: if !wakes.isEmpty { wakes.removeFirst() }
                }
            }
            #expect(wakes.count <= 1)
        }
        #expect(wakes.isEmpty)
        #expect(state == .playing)
    }

    private func play() -> MusicWingsHold.State {
        step(.hidden, .playback(.playing, wingsOnScreen: false, now: start), policy: .atOnce).state
    }

    private func hold(for seconds: TimeInterval) -> (state: MusicWingsHold.State, effects: [MusicWingsHold.Effect]) {
        step(play(), .playback(.paused, wingsOnScreen: true, now: start), policy: .after(seconds))
    }

    private func later(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    private func step(_ state: MusicWingsHold.State, _ event: MusicWingsHold.Event, policy: PauseCollapse) -> (state: MusicWingsHold.State, effects: [MusicWingsHold.Effect]) {
        let (next, effects) = MusicWingsHold.reduce(state, event, policy: policy)
        return (next, effects)
    }
}
