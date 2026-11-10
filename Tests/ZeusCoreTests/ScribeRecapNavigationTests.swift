import Testing
@testable import ZeusCore

@Suite("Scribe saved-source navigation")
struct ScribeRecapNavigationTests {
    @Test func everyActivePhaseRefusesSavedSourceNavigation() {
        let id = ScribeSessionID()
        let phases: [ScribePhase] = [.starting(id), .recording(id, since: 0),
                                    .ending(id, deadline: 9), .processing(id)]
        for phase in phases {
            #expect(ScribeRecapNavigation.decision(phase: phase, recapExists: true, isCancelled: false) == .busy)
        }
    }

    @Test func missingOrCancelledSourcesNeverCloseTheCurrentNotes() {
        let id = ScribeSessionID()
        for phase: ScribePhase in [.idle, .complete(id), .failed(id, reason: "Fixture")] {
            #expect(ScribeRecapNavigation.decision(phase: phase, recapExists: false, isCancelled: false) == .unavailable)
            #expect(ScribeRecapNavigation.decision(phase: phase, recapExists: true, isCancelled: true) == .unavailable)
        }
    }

    @Test func existingSourcesLeaveOnlyTerminalStagesBeforeOpening() {
        let id = ScribeSessionID()
        #expect(ScribeRecapNavigation.decision(phase: .idle, recapExists: true, isCancelled: false) == .open)
        for phase: ScribePhase in [.complete(id), .failed(id, reason: "Fixture")] {
            #expect(ScribeRecapNavigation.decision(phase: phase, recapExists: true, isCancelled: false) == .closeNotesAndOpen)
        }
    }
}
