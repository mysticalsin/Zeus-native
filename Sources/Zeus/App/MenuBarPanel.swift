import AppKit
import SwiftUI

/// Borderless, non-activating panel under the menu-bar icon. Closes on any click outside it.
@MainActor
final class MenuBarPanel: NSPanel {
    private var outsideClickMonitor: Any?
    private let measureContentSize: () -> NSSize

    init<Content: View>(rootView: Content) {
        let hosting = NSHostingController(rootView: rootView)
        measureContentSize = {
            hosting.sizeThatFits(in: NSSize(width: Theme.panelWidth, height: 10_000))
        }
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        contentViewController = hosting
        setAccessibilityLabel("ZEUS")
        setAccessibilityRole(.popover)
    }

    override var canBecomeKey: Bool { true }

    /// Escape closes the panel, like a menu or popover.
    override func cancelOperation(_ sender: Any?) { close() }

    func show(below statusItemFrame: NSRect) {
        setContentSize(measureContentSize())
        let x = statusItemFrame.midX - frame.width / 2
        let y = statusItemFrame.minY - frame.height - 6
        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    override func close() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        super.close()
    }
}
