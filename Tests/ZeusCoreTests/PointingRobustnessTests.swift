import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing robustness: stuck keys, sleep, wake, display change")
struct PointingRobustnessTests {
    private func holding() -> PointingKeyGesture {
        var gesture = PointingKeyGesture()
        _ = gesture.feed(.flags(keyCode: 59, modifiers: [.control]), at: 0)
        #expect(gesture.feed(.flags(keyCode: 58, modifiers: [.control, .option]), at: 0.05) == .began)
        return gesture
    }

    @Test func aMissedReleaseIsCaughtWhenTheLiveKeysAreUp() {
        var gesture = holding()
        #expect(gesture.tick(at: 1, liveModifiers: [.control, .option]) == nil)
        #expect(gesture.tick(at: 2, liveModifiers: []) == .holdTimedOut)
        #expect(!gesture.isActive)
    }

    @Test func aHoldPastTheBoundEndsEvenWhenTheLiveKeysAreUnknown() {
        var gesture = holding()
        #expect(gesture.tick(at: PointingKeyGesture.maxHold - 1, liveModifiers: nil) == nil)
        #expect(gesture.tick(at: PointingKeyGesture.maxHold + 1, liveModifiers: nil) == .holdTimedOut)
    }

    @Test func afterATimeoutANewHoldNeedsEveryKeyUpFirst() {
        var gesture = holding()
        _ = gesture.tick(at: 2, liveModifiers: [.control])
        // The stale state was cleared, but a modifier is still down: no new hold yet.
        #expect(gesture.feed(.flags(keyCode: 58, modifiers: [.control, .option]), at: 3) == nil)
        #expect(gesture.feed(.flags(keyCode: 58, modifiers: []), at: 3.1) == nil)
        _ = gesture.feed(.flags(keyCode: 59, modifiers: [.control]), at: 4)
        #expect(gesture.feed(.flags(keyCode: 58, modifiers: [.control, .option]), at: 4.05) == .began)
    }

    @Test func theWatchdogDoesNothingWhenNoHoldIsActive() {
        var gesture = PointingKeyGesture()
        #expect(gesture.tick(at: 1000, liveModifiers: nil) == nil)
    }

    @Test func sleepOrADisplayChangeCancelsAHoldAndBlocksRestartUntilKeysAreUp() {
        var gesture = holding()
        #expect(gesture.interrupt() == .cancelled)
        #expect(!gesture.isActive)
        #expect(gesture.feed(.flags(keyCode: 58, modifiers: [.control, .option]), at: 1) == nil)
        #expect(gesture.feed(.flags(keyCode: 58, modifiers: []), at: 1.1) == nil)
        _ = gesture.feed(.flags(keyCode: 59, modifiers: [.control]), at: 2)
        #expect(gesture.feed(.flags(keyCode: 58, modifiers: [.control, .option]), at: 2.05) == .began)
    }

    @Test func interruptingWithNoHoldReportsNothing() {
        var gesture = PointingKeyGesture()
        #expect(gesture.interrupt() == nil)
    }

    // MARK: Session

    private func listening() -> PointingSession {
        var session = PointingSession(); session.send(.keyDown); return session
    }

    @Test func aTimedOutHoldProcessesTheTurnLikeARelease() {
        var session = listening()
        let transition = session.send(.holdTimedOut)
        #expect(session.state == .processing)
        #expect(transition.effects.contains(.stopListening))
        var drawing = listening(); drawing.send(.strokeBegan)
        drawing.send(.holdTimedOut)
        #expect(drawing.state == .processing)
    }

    @Test func sleepWakeAndDisplayChangesCancelAHoldWithoutARequest() {
        for event in [PointingSession.Event.systemSleep, .systemWake, .displaysChanged] {
            var session = listening()
            let transition = session.send(event)
            #expect(session.state == .cancelled, "\(event)")
            #expect(transition.effects.contains(.discardCapture))
            #expect(!transition.effects.contains(.stopListening))
        }
    }

    @Test func sleepWakeAndDisplayChangesStopATurnInFlight() {
        for event in [PointingSession.Event.systemSleep, .systemWake, .displaysChanged] {
            var session = listening(); session.send(.keyUp)
            let before = session.generation
            let transition = session.send(event)
            #expect(session.state == .interrupted, "\(event)")
            #expect(transition.effects == [.stopOutput])
            #expect(session.generation == before + 1)
        }
    }

    @Test func systemEventsWhileIdleDoNothing() {
        var session = PointingSession()
        let transition = session.send(.displaysChanged)
        #expect(session.state == .idle && !transition.changed)
    }
}
