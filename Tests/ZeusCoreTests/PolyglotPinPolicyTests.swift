import Foundation
import Testing
@testable import ZeusCore

/// Pure decisions only: no window, capture or permission is involved.
@Suite struct PolyglotPinPolicyTests {
    private func context(tab: Bool = true, pinned: Bool = false, autoHide: Bool = true) -> PolyglotPinContext {
        PolyglotPinContext(isPolyglotTabSelected: tab, isPinned: pinned, autoHideEnabled: autoHide)
    }

    @Test func pinnedSurvivesPointerExitAndClickOutside() {
        let pinned = context(pinned: true)
        #expect(PolyglotPinPolicy.decide(.pointerExited, pinned) == .keepOpen)
        #expect(PolyglotPinPolicy.decide(.clickedOutside, pinned) == .keepOpen)
        #expect(PolyglotPinPolicy.keepsOpen(pinned))
    }

    @Test func explicitDismissClosesEvenWhenPinned() {
        #expect(PolyglotPinPolicy.decide(.explicitDismiss, context(pinned: true)) == .close)
        #expect(PolyglotPinPolicy.decide(.explicitDismiss, context(pinned: false)) == .close)
    }

    @Test func unpinRestoresAutoHide() {
        #expect(PolyglotPinPolicy.decide(.pointerExited, context(pinned: true)) == .keepOpen)
        #expect(PolyglotPinPolicy.decide(.pointerExited, context(pinned: false)) == .scheduleClose)
        #expect(PolyglotPinPolicy.decide(.clickedOutside, context(pinned: false)) == .close)
    }

    @Test func tabSwitchAwayFromPinnedPolyglotRestoresAutoHide() {
        let away = context(tab: false, pinned: true)
        #expect(!PolyglotPinPolicy.keepsOpen(away))
        #expect(PolyglotPinPolicy.decide(.pointerExited, away) == .scheduleClose)
        #expect(PolyglotPinPolicy.decide(.clickedOutside, away) == .close)
    }

    @Test func autoHideDisabledNeverSchedulesClose() {
        #expect(PolyglotPinPolicy.decide(.pointerExited, context(autoHide: false)) == .keepOpen)
        #expect(PolyglotPinPolicy.decide(.pointerExited, context(tab: false, pinned: true, autoHide: false)) == .keepOpen)
    }

    @Test func pinOnlyAppliesOnPolyglotTab() {
        let other = context(tab: false, pinned: true)
        #expect(!PolyglotPinPolicy.keepsOpen(other))
        #expect(PolyglotPinPolicy.decide(.clickedOutside, other) == .close)
    }
}
