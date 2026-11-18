import AppKit
import Testing
@testable import Zeus

/// The guide floats over System Settings and the Allow dialog. A step change must not take the keyboard
/// from whichever of those is frontmost. Return and Escape fire only after the guide itself is focused.
@MainActor
@Suite("Permission sweep guide keyboard", .serialized)
struct PermissionSweepGuideTests {
    @Test func aStepChangeWhileAnotherAppIsFrontmostDoesNotMakeThePanelKey() throws {
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
        #expect(!panel.becomesKeyOnlyIfNeeded)
        #expect(panel.canBecomeKey)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.isKeyWindow)
        if frontWasKey { #expect(front.isKeyWindow) }
        #expect(application.isActive == wasActive)
    }

    @Test func aClickInTheGuideArmsTheKeyboardWithoutShowTakingKey() throws {
        let application = NSApplication.shared
        // swift test is unbundled, so it has no LSUIElement and stays .regular. A synthetic
        // leftMouseDown never reaches the window server, and AppKit then activates a regular
        // process when the panel becomes key. Zeus is accessory (Info.plist LSUIElement and
        // setActivationPolicy in main.swift); a real click on this nonactivating panel does not.
        let originalPolicy = application.activationPolicy()
        if originalPolicy != .accessory {
            try #require(application.setActivationPolicy(.accessory))
        }
        defer {
            if originalPolicy != .accessory {
                _ = application.setActivationPolicy(originalPolicy)
            }
        }
        let front = KeyStandInWindow(contentRect: NSRect(x: 40, y: 40, width: 80, height: 40),
                                     styleMask: [.borderless],
                                     backing: .buffered,
                                     defer: false)
        front.orderFrontRegardless()
        front.makeKey()
        let runner = PermissionSweepRunner(services: OnboardingServices(permissions: PermissionsModel()))
        let guide = PermissionSweepGuide(runner: runner)
        defer {
            guide.close()
            front.orderOut(nil)
        }
        guide.show()
        guide.show()
        let panel = try #require(Mirror(reflecting: guide).descendant("panel") as? NSPanel)
        let content = try #require(panel.contentView)
        #expect(!panel.isKeyWindow)
        #expect(panel.canBecomeKey)
        #expect(!panel.becomesKeyOnlyIfNeeded)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(application.activationPolicy() == .accessory)
        let wasActive = application.isActive
        let point = NSPoint(x: content.bounds.midX, y: content.bounds.midY)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
                                                    modifierFlags: [],
                                                    timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: panel.windowNumber,
                                                    context: nil,
                                                    eventNumber: 1,
                                                    clickCount: 1,
                                                    pressure: 1))
        panel.sendEvent(down)
        #expect(panel.isKeyWindow)
        #expect(application.isActive == wasActive)
    }
}

/// A borderless window that can be key, standing in for System Settings or the Allow dialog.
private final class KeyStandInWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
