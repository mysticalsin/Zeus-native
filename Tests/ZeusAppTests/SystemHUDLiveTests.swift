import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Section 10 (Glance-style system HUDs) tests that need the live `TopBarModel`, as opposed to
/// the pure `ZeusCoreTests.SystemHUDTests`/`NotchLightsTests`.
@MainActor @Suite struct SystemHUDLiveTests {
    // H1/top-glow-only-on-trigger: nothing is lit before anything happens.
    @Test func idleIsDark() {
        let topBar = TopBarModel()
        #expect(topBar.lights.isEmpty)
        #expect(!topBar.isDraggingFiles)
        #expect(!topBar.micListening)
    }

    // H2: repeated changes continue the SAME light (same id, extended deadline), not a stack of
    // appended lights.
    @Test func hudLevelUpdatesInPlace() {
        let id = "lights.hud.volume"
        let store = SettingsStore.shared
        let saved = store.string(id)
        defer { store.set(id, saved) }
        store.set(id, "true")
        let topBar = TopBarModel()
        topBar.presentSystemHUD(.volume, value: 0.2, muted: false)
        let firstID = topBar.lights.first?.id
        for value in [0.3, 0.4, 0.5, 0.55] {
            topBar.presentSystemHUD(.volume, value: value, muted: false)
        }
        #expect(topBar.lights.count == 1) // one light after 5 rapid changes, not 5
        #expect(topBar.lights.first?.id == firstID) // same light, continued
        if case .hudLevel(_, let v, _, _, _) = topBar.lights.first?.kind {
            #expect(abs(v - 0.55) < 0.001)
        } else {
            Issue.record("expected a .hudLevel light")
        }
    }

    // H3: lowering the value after it was raised retracts the arm (previousLevel is the last
    // value, not 0), and hitting a bound again adds a limit echo.
    @Test func presentSystemHUDTracksPreviousLevelAndLimitEcho() {
        let id = "lights.hud.volume"
        let store = SettingsStore.shared
        let saved = store.string(id)
        defer { store.set(id, saved) }
        store.set(id, "true")
        let topBar = TopBarModel()
        topBar.presentSystemHUD(.volume, value: 1.0, muted: false)
        topBar.presentSystemHUD(.volume, value: 1.0, muted: false) // same direction at the bound
        guard case .hudLevel(_, let value, let previous, _, let limitEcho) = topBar.lights.first?.kind else {
            Issue.record("expected a .hudLevel light")
            return
        }
        #expect(abs(value - previous) < 0.001) // already at the bound: value == previous
        #expect(limitEcho)

        topBar.presentSystemHUD(.volume, value: 0.2, muted: false) // now lower it
        guard case .hudLevel(_, let value2, let previous2, _, let limitEcho2) = topBar.lights.first?.kind else {
            Issue.record("expected a .hudLevel light")
            return
        }
        #expect(previous2 > value2) // retracting, not regrowing from zero
        #expect(!limitEcho2)
    }
}
