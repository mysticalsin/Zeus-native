import Testing
@testable import ZeusCore

@Suite("Hover expand and a notification") struct NotchHoverNotifyTests {
    @Test func hoverExpandDefersAnAgentNoticeAndDoesNotOpenWhileThePointerIsOnIt() {
        // A Claude card is up. Moving onto the capsule cancels a dwell that already started.
        #expect(NotchHoverNotify.cancelArmedHover(pointerOnNotification: true, hoverArmed: true))
        #expect(!NotchHoverNotify.cancelArmedHover(pointerOnNotification: true, hoverArmed: false))
        #expect(!NotchHoverNotify.cancelArmedHover(pointerOnNotification: false, hoverArmed: true))

        // The dwell does not open while the pointer is on that capsule, from either closed or peek.
        #expect(!NotchHoverNotify.commitHover(inHotZone: true, pointerOnNotification: true, surface: .closed))
        #expect(!NotchHoverNotify.commitHover(inHotZone: true, pointerOnNotification: true, surface: .peek))
        #expect(!NotchHoverNotify.commitHover(inHotZone: false, pointerOnNotification: false, surface: .peek))
        #expect(NotchHoverNotify.commitHover(inHotZone: true, pointerOnNotification: false, surface: .peek))
        #expect(NotchHoverNotify.commitHover(inHotZone: true, pointerOnNotification: false, surface: .closed))
        #expect(!NotchHoverNotify.commitHover(inHotZone: true, pointerOnNotification: false, surface: .panel))

        // Arriving during the dwell, or while the panel is open, does not change the surface.
        #expect(NotchHoverNotify.deferAgentPeek(surface: .closed, hoverArmed: true))
        #expect(NotchHoverNotify.deferAgentPeek(surface: .peek, hoverArmed: true))
        #expect(NotchHoverNotify.deferAgentPeek(surface: .panel, hoverArmed: false))
        #expect(!NotchHoverNotify.deferAgentPeek(surface: .closed, hoverArmed: false))

        // The card's own timer waits out the dwell, then folds only a peek.
        #expect(NotchHoverNotify.deferPeekFold(surface: .peek, hoverArmed: true))
        #expect(!NotchHoverNotify.deferPeekFold(surface: .peek, hoverArmed: false))
        #expect(!NotchHoverNotify.deferPeekFold(surface: .panel, hoverArmed: true))
        #expect(!NotchHoverNotify.deferPeekFold(surface: .closed, hoverArmed: true))

        // Opening from the card drops it instead of reflowing it into the panel frame.
        #expect(NotchHoverNotify.dropPeekContent(from: .peek, to: .panel))
        #expect(!NotchHoverNotify.dropPeekContent(from: .closed, to: .panel))
        #expect(!NotchHoverNotify.dropPeekContent(from: .peek, to: .closed))
    }

    @Test func anAlertStaysOffTheStackUntilTheIslandIsClosedAndIdle() {
        #expect(NotchHoverNotify.alertAdmission(surface: .closed, hoverArmed: false, whileOpen: false) == .post)
        #expect(NotchHoverNotify.alertAdmission(surface: .closed, hoverArmed: true, whileOpen: false) == .hold)
        #expect(NotchHoverNotify.alertAdmission(surface: .panel, hoverArmed: false, whileOpen: true) == .hold)
        #expect(NotchHoverNotify.alertAdmission(surface: .panel, hoverArmed: false, whileOpen: false) == .drop)
        #expect(NotchHoverNotify.alertAdmission(surface: .peek, hoverArmed: false, whileOpen: false) == .drop)
        #expect(NotchHoverNotify.alertAdmission(surface: .peek, hoverArmed: true, whileOpen: false) == .hold)

        #expect(!NotchHoverNotify.mountAlert(surface: .closed, hoverArmed: true, hasAlert: true))
        #expect(!NotchHoverNotify.mountAlert(surface: .panel, hoverArmed: false, hasAlert: true))
        #expect(!NotchHoverNotify.mountAlert(surface: .peek, hoverArmed: false, hasAlert: true))
        #expect(!NotchHoverNotify.mountAlert(surface: .closed, hoverArmed: false, hasAlert: false))
        #expect(NotchHoverNotify.mountAlert(surface: .closed, hoverArmed: false, hasAlert: true))
    }
}
