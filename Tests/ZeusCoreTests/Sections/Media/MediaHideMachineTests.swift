import Foundation
import Testing
@testable import ZeusCore

@Suite("Hide on pause") struct MediaHideMachineTests {
    private let start = Date(timeIntervalSince1970: 10_000)

    @Test func namesTheThreePoliciesAndStartsVisible() {
        #expect(MediaHidePolicy.allCases.map(\.title) == ["Instantly", "After a delay", "Never"])
        #expect(MediaHidePolicy.delay == 5)
        #expect(MediaHidePolicy(stored: nil) == .never)
        #expect(MediaHidePolicy(stored: "later") == .never)
        #expect(MediaHidePolicy(stored: "instantly") == .instantly)
        let machine = MediaHideMachine()
        #expect(machine.policy == .never)
        #expect(machine.state == .visible)
    }

    @Test func neverKeepsThePlayerShown() {
        var machine = MediaHideMachine(policy: .never)
        let step = machine.send(.paused(at: start), reduceMotion: false)
        #expect(step.accepted)
        #expect(step.state == .visible)
        #expect(step.visible)
        #expect(step.animationDuration == 0)
    }

    @Test func instantlyHidesAndASecondPauseDoesNotRestart() {
        var machine = MediaHideMachine(policy: .instantly)
        let first = machine.send(.paused(at: start), reduceMotion: false)
        #expect(first.accepted)
        #expect(first.state == .hidden)
        #expect(first.animationDuration == MotionTokens.panelClose.response)
        let second = machine.send(.paused(at: start.addingTimeInterval(1)), reduceMotion: false)
        #expect(!second.accepted)
        #expect(second.state == .hidden)
        #expect(second.animationDuration == 0)
    }

    @Test func delayHidesOnTheBoundaryAndNotBefore() {
        var machine = MediaHideMachine(policy: .afterDelay)
        let paused = machine.send(.paused(at: start), reduceMotion: false)
        #expect(paused.state == .counting(since: start))
        let early = machine.send(.timePassed(at: start.addingTimeInterval(MediaHidePolicy.delay - 0.001)), reduceMotion: false)
        #expect(early.accepted)
        #expect(early.state == .counting(since: start))
        let again = machine.send(.paused(at: start.addingTimeInterval(1)), reduceMotion: false)
        #expect(!again.accepted)
        #expect(again.state == .counting(since: start))
        let due = machine.send(.timePassed(at: start.addingTimeInterval(MediaHidePolicy.delay)), reduceMotion: false)
        #expect(due.accepted)
        #expect(due.state == .hidden)
        #expect(due.visible == false)
    }

    @Test func aTickOutsideTheWaitIsRejected() {
        var visible = MediaHideMachine(policy: .afterDelay)
        #expect(!visible.send(.timePassed(at: start), reduceMotion: false).accepted)
        #expect(visible.state == .visible)
        var counting = MediaHideMachine(policy: .afterDelay, state: .counting(since: start))
        let backwards = counting.send(.timePassed(at: start.addingTimeInterval(-0.1)), reduceMotion: false)
        #expect(!backwards.accepted)
        #expect(backwards.state == .counting(since: start))
        var hidden = MediaHideMachine(policy: .instantly, state: .hidden)
        #expect(!hidden.send(.timePassed(at: start), reduceMotion: true).accepted)
    }

    @Test func playAndClearAlwaysShow() {
        for policy in MediaHidePolicy.allCases {
            for state in [MediaHideMachine.State.hidden, .counting(since: start), .visible] {
                var machine = MediaHideMachine(policy: policy, state: state)
                let played = machine.send(.beganPlaying, reduceMotion: true)
                #expect(played.accepted)
                #expect(played.state == .visible)
                #expect(played.animationDuration == 0)
                var concealed = MediaHideMachine(policy: policy, state: .hidden)
                let cleared = concealed.send(.cleared, reduceMotion: false)
                #expect(cleared.accepted)
                #expect(cleared.state == .visible)
            }
        }
    }

    @Test func changingPolicyMovesAPausedPlayer() {
        var counting = MediaHideMachine(policy: .afterDelay, state: .counting(since: start))
        #expect(counting.send(.policy(.instantly), reduceMotion: false).state == .hidden)
        counting = MediaHideMachine(policy: .afterDelay, state: .counting(since: start))
        #expect(counting.send(.policy(.never), reduceMotion: false).state == .visible)
        counting = MediaHideMachine(policy: .afterDelay, state: .counting(since: start))
        #expect(counting.send(.policy(.afterDelay), reduceMotion: false).state == .counting(since: start))

        var hidden = MediaHideMachine(policy: .instantly, state: .hidden)
        #expect(hidden.send(.policy(.never), reduceMotion: false).state == .visible)
        hidden = MediaHideMachine(policy: .instantly, state: .hidden)
        #expect(hidden.send(.policy(.instantly), reduceMotion: false).state == .hidden)
        hidden = MediaHideMachine(policy: .instantly, state: .hidden)
        #expect(hidden.send(.policy(.afterDelay), reduceMotion: false).state == .hidden)

        var shown = MediaHideMachine(policy: .never)
        #expect(shown.send(.policy(.instantly), reduceMotion: false).state == .visible)
    }

    @Test func retargetWhilePausedUsesTheNewPolicy() {
        var machine = MediaHideMachine(policy: .never, state: .visible)
        let instant = MediaHideMachine.retarget(&machine, to: .instantly, playing: false, at: start, reduceMotion: false)
        #expect(instant.state == .hidden)
        let never = MediaHideMachine.retarget(&machine, to: .never, playing: false, at: start, reduceMotion: true)
        #expect(never.state == .visible)
        #expect(never.animationDuration == 0)
        let playing = MediaHideMachine.retarget(&machine, to: .instantly, playing: true, at: start, reduceMotion: false)
        #expect(playing.state == .visible)
    }

    @Test func reducedMotionRemovesTheHideAnimation() {
        var motion = MediaHideMachine(policy: .instantly)
        var still = motion
        let animated = motion.send(.paused(at: start), reduceMotion: false)
        let reduced = still.send(.paused(at: start), reduceMotion: true)
        #expect(animated.state == reduced.state)
        #expect(animated.animationDuration > 0)
        #expect(reduced.animationDuration == 0)
    }

    @Test func countingExistsOnlyWhileTheDelayPolicyIsActive() {
        let dates = [0.0, 1, 4.9, 5, 5.1].map { Date(timeIntervalSince1970: $0) }
        for policy in MediaHidePolicy.allCases {
            for reduce in [false, true] {
                var machine = MediaHideMachine(policy: policy)
                for date in dates {
                    _ = machine.send(.paused(at: date), reduceMotion: reduce)
                    _ = machine.send(.timePassed(at: date.addingTimeInterval(MediaHidePolicy.delay)), reduceMotion: reduce)
                    if policy != .afterDelay {
                        if case .counting = machine.state {
                            Issue.record("\(policy) entered the delay wait")
                        }
                    }
                    _ = machine.send(.policy(policy), reduceMotion: reduce)
                }
                _ = machine.send(.beganPlaying, reduceMotion: reduce)
                #expect(machine.state == .visible)
                #expect(machine.state != .hidden)
            }
        }
    }
}
