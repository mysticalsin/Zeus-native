import Foundation
import Testing
import ZeusCore
@testable import Zeus

@MainActor
@Suite("Record page snapshot fixtures")
struct RecordlySnapshotFixtureTests {
    private func controller(_ state: RecordlyController.SnapshotState, displays: [RecordlySourceSelection.CatalogSnapshot.Display]? = nil) -> RecordlyController {
        RecordlySnapshotFixtures.controller(displays: displays ?? [RecordlySnapshotFixtures.builtIn, RecordlySnapshotFixtures.external],
                                            granted: true, state: state)
    }

    /// QA M12: the "countdown" snapshot showed the idle two-display screen because the seeded press found no
    /// ready source, so nothing was counting.
    @Test func theCountdownFixtureIsActuallyCountingDown() {
        let counting = controller(.countdown(2))
        #expect(counting.isCountingDown, "the countdown snapshot must show a countdown, not the idle screen")
        #expect(counting.countdownRemaining == 2)
    }

    @Test func everyFixtureStateShowsItsOwnState() {
        #expect(!controller(.idle).isCountingDown)
        #expect(controller(.recording(elapsed: 74)).elapsed == 74)
        for (name, displays, granted, state) in RecordlySnapshotFixtures.pageStates {
            let fixture = RecordlySnapshotFixtures.controller(displays: displays, granted: granted, state: state)
            if case .countdown = state { #expect(fixture.isCountingDown, "\(name)") }
        }
    }
}
