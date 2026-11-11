import Testing
import ZeusCore
@testable import Zeus

/// Presentation only: never starts a capture or opens an OS permission prompt.
@MainActor @Suite struct PolyglotPinTests {
    @Test func pinnedPageSurvivesAutomaticDismissButCanBeDismissedExplicitly() {
        let controller = NotchController()
        let topBar = TopBarModel()
        topBar.selectedTab = .polyglot
        controller.topBar = topBar
        controller.isPolyglotPinned = { true }
        controller.show(.panel)
        controller.dismissAutomatically()
        #expect(controller.model.presentation == .panel)
        controller.show(.closed)
        #expect(controller.model.presentation == .closed)
        controller.show(.panel)
        controller.dismissAutomatically()
        #expect(controller.model.presentation == .panel)
    }

    @Test func unpinAndOtherTabsUseNormalDismissal() {
        let controller = NotchController()
        let topBar = TopBarModel()
        topBar.selectedTab = .polyglot
        controller.topBar = topBar
        controller.isPolyglotPinned = { false }
        controller.show(.panel)
        controller.dismissAutomatically()
        #expect(controller.model.presentation == .closed)
        controller.isPolyglotPinned = { true }
        topBar.selectedTab = .home
        controller.show(.panel)
        controller.dismissAutomatically()
        #expect(controller.model.presentation == .closed)
    }

    @Test func stopKeepsPinAndBarVisible() {
        let polyglot = PolyglotController.shared
        let wasPinned = polyglot.isPinned
        defer { if polyglot.isPinned != wasPinned { polyglot.togglePin() } }
        if !polyglot.isPinned { polyglot.togglePin() }
        let controller = NotchController()
        let topBar = TopBarModel()
        topBar.selectedTab = .polyglot
        controller.topBar = topBar
        // Uses the real isPinned. Stop with nothing live only resets state; it never captures.
        controller.show(.panel)
        polyglot.stop()
        #expect(polyglot.isPinned)
        controller.dismissAutomatically()
        #expect(controller.model.presentation == .panel)
    }

    @Test func explicitDismissClosesPinnedBar() {
        let controller = NotchController()
        let topBar = TopBarModel()
        topBar.selectedTab = .polyglot
        controller.topBar = topBar
        controller.isPolyglotPinned = { true }
        controller.show(.panel)
        // The Dismiss button goes through NotchControllerBridge.controller?.dismissExplicitly().
        NotchControllerBridge.controller = controller
        defer { NotchControllerBridge.controller = nil }
        NotchControllerBridge.controller?.dismissExplicitly()
        #expect(controller.model.presentation == .closed)
    }

    @Test func unpinRestoresAutomaticDismissal() {
        let controller = NotchController()
        let topBar = TopBarModel()
        topBar.selectedTab = .polyglot
        controller.topBar = topBar
        var pinned = true
        controller.isPolyglotPinned = { pinned }
        controller.show(.panel)
        controller.dismissAutomatically()
        #expect(controller.model.presentation == .panel)
        pinned = false
        controller.dismissAutomatically()
        #expect(controller.model.presentation == .closed)
    }
}
