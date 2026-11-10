import Testing
@testable import Zeus

/// GATE added 2 Nov 22:50 BRT: a stale Accessibility grant (pointing at an old build) must show
/// a visible notice, not fail silently. `AppDelegate` turns this into `topBar.show(.permission(...))`;
/// this tests the pure decision and message.
@Suite struct KeyAccessNoticeTests {
    @Test func noNoticeWhenGranted() {
        #expect(KeyAccessNotice.cue(granted: true) == nil)
    }

    @Test func noticeWhenNotGrantedPointsAtAccessibility() {
        let notice = KeyAccessNotice.cue(granted: false)
        #expect(notice?.pane == "Privacy_Accessibility")
        #expect(notice?.text.isEmpty == false)
    }
}
