import CoreGraphics
import Testing
import ZeusCore
@testable import Zeus

/// A notification that is already on screen must not stretch the hover panel past a normal open.
@Suite("Notch layout bounds")
struct NotchLayoutBoundsTests {
    @Test func aLongNotificationDoesNotStretchTheHomeHover() {
        let plain = NotchView.topBarPanelSize(barHeight: 32, hasApproval: false, extra: 0, home: true)
        let noted = NotchView.topBarPanelSize(barHeight: 32, hasApproval: true, extra: 480, home: true)
        #expect(noted.width == plain.width)
        #expect(noted.height == plain.height)
        #expect(noted.width <= NotchLayoutBounds.maxWidth)
        #expect(noted.height <= NotchLayoutBounds.maxHeight)
    }

    @Test func everyPanelCombinationStaysInsideTheDesignedMaximum() {
        for factors in NotchLayoutBounds.combinations {
            let size = NotchLayoutBounds.size(factors)
            #expect(size.width <= NotchLayoutBounds.maxWidth, "\(factors)")
            #expect(size.height <= NotchLayoutBounds.maxHeight, "\(factors)")
            #expect(size.width > 0 && size.height > 0)
        }
    }

    @Test func hoverWithANotificationMatchesAPlainHover() {
        let plain = NotchLayoutBounds.size(.init(hover: true, home: true))
        let noted = NotchLayoutBounds.size(.init(hover: true, home: true, notification: true, approval: true, approvalExtra: 640))
        #expect(noted == plain)
    }
}
