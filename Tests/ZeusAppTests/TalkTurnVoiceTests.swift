import Foundation
import Testing
@testable import Zeus

/// The talk-turn voice path with an AirPods-style headset: capture survives a profile change, and
/// the microphone and output engine are used the way the turn needs them. No audio hardware.
@Suite("Talk turn voice", .serialized)
struct TalkTurnVoiceTests {
    private struct Boom: Error {}

    /// Spies in place of the engine: they record the order of calls.
    private final class Spy: @unchecked Sendable {
        var calls: [String] = []
        var tapAccepted = true
        var restartThrows = false
        var failures: [CaptureRecovery.Outcome] = []
    }

    private func fire(_ spy: Spy, cancelsTurn: Bool = false, ownsSession: Bool = true) -> CaptureRecovery.Action {
        CaptureRecovery.handle(
            cancelsTurn: cancelsTurn, ownsSession: ownsSession,
            cancelTurn: { spy.calls.append("cancel") },
            reinstallTap: { spy.calls.append("tap"); return spy.tapAccepted },
            restartEngine: { spy.calls.append("restart"); if spy.restartThrows { throw Boom() } },
            recoveryFailed: { spy.failures.append($0) })
    }

    @Test func aConfigurationChangeReinstallsTheTapThenRestartsTheEngineAndKeepsTheTurn() {
        let spy = Spy()
        #expect(fire(spy) == .rebuild)
        #expect(spy.calls == ["tap", "restart"])
        #expect(!spy.calls.contains("cancel"))
        #expect(spy.failures.isEmpty)
    }

    @Test func aChangeAfterTheTurnEndedDoesNothing() {
        let spy = Spy()
        #expect(fire(spy, ownsSession: false) == .ignore)
        #expect(spy.calls.isEmpty)
    }

    @Test func theExplanationPolicyStillCancelsInsteadOfRecovering() {
        let spy = Spy()
        #expect(fire(spy, cancelsTurn: true) == .cancelTurn)
        #expect(spy.calls == ["cancel"])
    }

    @Test func anInputWithoutAFormatWaitsForTheNextChangeInsteadOfEndingTheTurn() {
        let spy = Spy()
        spy.tapAccepted = false
        _ = fire(spy)
        #expect(spy.calls == ["tap"], "no restart without a tap")
        #expect(spy.failures == [.inputUnavailable])
        #expect(!CaptureRecovery.Outcome.inputUnavailable.endsTurn)
    }

    @Test func anEngineThatWillNotRestartIsReportedAndEndsTheTurn() {
        let spy = Spy()
        spy.restartThrows = true
        _ = fire(spy)
        #expect(spy.calls == ["tap", "restart"])
        #expect(spy.failures == [.restartFailed])
        #expect(CaptureRecovery.Outcome.restartFailed.endsTurn)
    }

    @Test func twoChangesInARowEachRebuild() {
        let spy = Spy()
        _ = fire(spy)
        _ = fire(spy)
        #expect(spy.calls == ["tap", "restart", "tap", "restart"])
    }
}
