import Testing
@testable import ZeusCore

@Suite("Top bar position")
struct TopBarPositionTests {
    @Test func notchedDisplayDefaultsToASmallDrop() {
        #expect(TopBarPosition.automaticOffset(notchHeight: 32) == 10)
        #expect(TopBarPosition.automaticOffset(notchHeight: 38) == 12)
        #expect(TopBarPosition.resolved(chosen: nil, notchHeight: 38) == 12)
    }

    @Test func displayWithoutANotchDefaultsToZero() {
        #expect(TopBarPosition.automaticOffset(notchHeight: 0) == 0)
        #expect(TopBarPosition.automaticOffset(notchHeight: -4) == 0)
        #expect(TopBarPosition.automaticOffset(notchHeight: .nan) == 0)
        #expect(TopBarPosition.resolved(chosen: nil, notchHeight: 0) == 0)
    }

    @Test func aChosenValueWinsAndIsClamped() {
        #expect(TopBarPosition.resolved(chosen: 0, notchHeight: 38) == 0)
        #expect(TopBarPosition.resolved(chosen: 16, notchHeight: 0) == 16)
        #expect(TopBarPosition.resolved(chosen: 99, notchHeight: 38) == 24)
        #expect(TopBarPosition.resolved(chosen: -5, notchHeight: 38) == 0)
        #expect(TopBarPosition.resolved(chosen: 7, notchHeight: 38) == 8)
        #expect(TopBarPosition.resolved(chosen: .infinity, notchHeight: 38) == 0)
    }

    @Test func theOpenPanelNeverDrops() {
        #expect(TopBarPosition.applied(resolved: 12, panelOpen: true) == 0)
        #expect(TopBarPosition.applied(resolved: 12, panelOpen: false) == 12)
        #expect(TopBarPosition.applied(resolved: 60, panelOpen: false) == 24)
    }
}
