import Testing
@testable import Zeus

/// A notification that is already on screen must not stretch the hover panel past a normal open.
@Suite("Notch layout bounds")
struct NotchLayoutBoundsTests {
    @Test func aLongNotificationDoesNotStretchTheHomeHover() {
        let plain = NotchView.topBarPanelSize(barHeight: 32, hasApproval: false, extra: 0, home: true)
        let noted = NotchView.topBarPanelSize(barHeight: 32, hasApproval: true, extra: 480, home: true)
        #expect(noted.width == plain.width)
        #expect(noted.height == plain.height)
    }
}
