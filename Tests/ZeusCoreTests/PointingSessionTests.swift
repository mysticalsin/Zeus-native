import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing session state machine")
struct PointingSessionTests {
    private func listening() -> PointingSession {
        var session = PointingSession(); session.send(.keyDown); return session
    }

    @Test func keyDownStartsListeningAndBumpsTheGeneration() {
        var session = PointingSession()
        let transition = session.send(.keyDown)
        #expect(session.state == .listening)
        #expect(transition.effects == [.startListening])
        #expect(session.generation == 1)
    }

    @Test func drawingIsASubstateOfTheHold() {
        var session = listening()
        session.send(.strokeBegan); #expect(session.state == .drawing)
        session.send(.strokeEnded); #expect(session.state == .listening)
    }

    @Test func releaseGoesToProcessingAndFinishesListening() {
        var session = listening()
        let transition = session.send(.keyUp)
        #expect(session.state == .processing)
        #expect(transition.effects.contains(.stopListening))
        session.send(.firstPlaybackStart); #expect(session.state == .speaking)
        session.send(.buffering); #expect(session.state == .processing)
        session.send(.firstPlaybackStart)
        session.send(.turnCompleted); #expect(session.state == .idle)
    }

    @Test func spoilCancelsWithoutAnyRequest() {
        var session = listening()
        let transition = session.send(.spoiled)
        #expect(session.state == .cancelled)
        #expect(transition.effects.contains(.discardCapture))
        #expect(!transition.effects.contains(.stopListening))
        session.send(.cleanedUp); #expect(session.state == .idle)
    }

    @Test func escapeWhileHoldingCancelsAndEscapeWhileSpeakingInterrupts() {
        var held = listening()
        held.send(.escape); #expect(held.state == .cancelled)
        var speaking = listening()
        speaking.send(.keyUp); speaking.send(.firstPlaybackStart)
        let transition = speaking.send(.escape)
        #expect(speaking.state == .interrupted)
        #expect(transition.effects == [.stopOutput])
        speaking.send(.cleanedUp); #expect(speaking.state == .idle)
    }

    @Test func emptyTranscriptCancels() {
        var session = listening()
        session.send(.keyUp)
        session.send(.emptyTranscript)
        #expect(session.state == .cancelled)
    }

    @Test func bargeInStopsOutputThenListens() {
        for setup in 0..<2 {
            var session = listening()
            session.send(.keyUp)
            if setup == 1 { session.send(.firstPlaybackStart) }
            let transition = session.send(.keyDown)
            #expect(session.state == .listening)
            #expect(transition.effects == [.stopOutput, .startListening])
        }
    }

    @Test func lateCallbacksFromAnOldGenerationAreDropped() {
        var session = listening()
        let old = session.generation
        session.send(.keyUp)
        session.send(.keyDown) // barge-in bumps the generation
        let late = session.send(.firstPlaybackStart, generation: old)
        #expect(!late.changed)
        #expect(session.state == .listening)
        #expect(!session.isCurrent(old))
    }

    @Test func failureAndPermissionLossStopEverythingWithAVisibleReason() {
        var session = listening()
        let transition = session.send(.failure("No connection."))
        #expect(session.state == .failed("No connection."))
        #expect(transition.effects.contains(.stopOutput) && transition.effects.contains(.discardCapture))
        session.send(.cleanedUp); #expect(session.state == .idle)
        var lost = listening()
        lost.send(.permissionLost)
        if case .failed = lost.state {} else { Issue.record("expected failed") }
    }

    @Test func guidanceIsStubbedButTheTransitionsExist() {
        var session = listening()
        session.send(.keyUp); session.send(.firstPlaybackStart)
        session.send(.guidanceAdmitted); #expect(session.state == .guiding)
        session.send(.clickInTarget); #expect(session.state == .processing)
    }

    @Test func idleIgnoresStrayEvents() {
        var session = PointingSession()
        for event: PointingSession.Event in [.keyUp, .spoiled, .escape, .firstPlaybackStart, .failure("x"), .permissionLost] {
            #expect(!session.send(event).changed)
        }
        #expect(session.state == .idle)
    }
}
