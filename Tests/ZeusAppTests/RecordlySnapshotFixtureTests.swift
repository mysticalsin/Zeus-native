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

    /// The snapshot renderer draws one fixture at 1x, 2x and again flat; each render ends with the page going away,
    /// which cancels a real countdown. Only the first draw showed it, so the files people open were idle.
    @Test func theCountdownFixtureSurvivesTheRenderEndingThePage() {
        let counting = controller(.countdown(2))
        counting.pageDisappeared()
        #expect(counting.isCountingDown, "later renders of the same fixture must still show the countdown")
    }

    /// The page opening runs a thumbnail refresh; on a fixture it must keep the drawn still and take no capture.
    @Test func aFixtureKeepsItsDrawnThumbnailWhenThePageOpens() async throws {
        let fixture = controller(.countdown(2))
        let before = try #require(fixture.thumbnail)
        fixture.pageAppeared()
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.thumbnail === before, "a capture replaced the drawn still")
        fixture.pageDisappeared()
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
