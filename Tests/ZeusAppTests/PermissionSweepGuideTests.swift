import AppKit
import Testing
@testable import Zeus

/// The guide floats over System Settings and the Allow dialog. A step change must not take the keyboard
/// from whichever of those is frontmost. Return and Escape fire only after the guide itself is focused.
@MainActor
@Suite("Permission sweep guide keyboard", .serialized)
struct PermissionSweepGuideTests {
    @Test func aStepChangeWhileAnotherAppIsFrontmostDoesNotMakeThePanelKey() {
        let application = NSApplication.shared
        let wasActive = application.isActive
        let front = KeyStandInWindow(contentRect: NSRect(x: 40, y: 40, width: 80, height: 40),
                                     styleMask: [.borderless],
                                     backing: .buffered,
                                     defer: false)
        front.orderFrontRegardless()
        front.makeKey()
        let frontWasKey = front.isKeyWindow
        let runner = PermissionSweepRunner(services: OnboardingServices(permissions: PermissionsModel()))
        let guide = PermissionSweepGuide(runner: runner)
        defer {
            guide.close()
            front.orderOut(nil)
        }
        // Each step calls show(). The second call is the step change while the other window is frontmost.
        guide.show()
        guide.show()
        let panel = try #require(Mirror(reflecting: guide).descendant("panel") as? NSPanel)
        #expect(panel.becomesKeyOnlyIfNeeded)
        #expect(panel.canBecomeKey)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.isKeyWindow)
        if frontWasKey { #expect(front.isKeyWindow) }
        #expect(application.isActive == wasActive)
    }
}

/// A borderless window that can be key, standing in for System Settings or the Allow dialog.
private final class KeyStandInWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
