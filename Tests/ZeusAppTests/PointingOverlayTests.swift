import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Own-process panels only: nothing is captured, shown to the user, or sent anywhere. With no
/// display attached (a headless runner) the overlay has no panels and these checks hold vacuously,
/// which is why each one also asserts the policy that does not need a screen.
@MainActor
@Suite("Pointing overlay windows", .serialized)
struct PointingOverlayTests {
    @Test func theInkPanelsNeverBecomeKeyOrMainAndIgnoreTheMouse() {
        let overlay = MarkOverlay.shared
        overlay.show(capturingMouse: false)
        defer { overlay.hide() }
        #expect(!overlay.capturesMouse)
        for window in overlay.ownedWindows {
            #expect(!window.canBecomeKey && !window.canBecomeMain)
            #expect(window.ignoresMouseEvents)
            #expect(window.styleMask.contains(.nonactivatingPanel))
            #expect(window.sharingType == .none)
            #expect(!window.isKeyWindow && !window.isMainWindow)
        }
        #expect(overlay.ownedWindows.count == NSScreen.screens.count)
    }

    @Test func hidingRemovesEveryPanel() {
        let overlay = MarkOverlay.shared
        overlay.show(capturingMouse: false)
        overlay.hide()
        #expect(overlay.ownedWindows.isEmpty && !overlay.capturesMouse)
    }
}
