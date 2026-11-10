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
}
