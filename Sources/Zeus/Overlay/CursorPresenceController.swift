import AppKit
import QuartzCore
import ZeusCore

/// P0 item I: "Zeus next to the cursor". Generic, reusable cursor-following positioner for a
/// presence window (the dictation recorder pill today; any other "Zeus is here" window could
/// reuse it the same way): anchors near the pointer using `ZeusCore.CursorAnchor`, follows with
/// `ZeusCore.SpringFollow`'s no-jitter ease (the same shape `BuddyController` already uses for
/// the spark), multi-display aware, honours Reduce Motion, and tracks only while something is
/// being positioned -- the global mouse monitor and display link are both removed on `stop()`,
/// so an idle Mac with nothing summoned costs nothing.
@MainActor
final class CursorPresenceController {
    static let shared = CursorPresenceController()

    static let settingID = "presence.nearCursor"

    static var isEnabled: Bool {
        get { SettingsStore.shared.bool(settingID) }
        set { SettingsStore.shared.set(settingID, newValue ? "true" : "false") }
    }

    private weak var panel: NSPanel?
    private var sizeProvider: (() -> CGSize)?
    private var caretProvider: () -> CGRect? = { nil }
    private var displayLink: CADisplayLink?
    private var mouseMonitors: [Any] = []
    private var position: CGPoint = .zero
    private var lastTimestamp: CFTimeInterval = 0

    /// True while a window is actively being positioned near the cursor (for `zeus debug
    /// hud-state`/tests, and so a second `track` call on the same panel is a cheap no-op check).
    private(set) var isTracking = false

    /// Starts anchoring `panel` near the pointer. A no-op when the setting is off (the caller's
    /// existing fixed placement is left untouched) -- check `CursorPresenceController.isEnabled`
    /// first if the caller needs to know which placement it's about to use.
    func track(_ panel: NSPanel, size: @escaping () -> CGSize, caretRect: @escaping () -> CGRect? = { nil }) {
        guard Self.isEnabled else { return }
        stop()
        self.panel = panel
        self.sizeProvider = size
        self.caretProvider = caretRect
        let target = targetFrame()
        position = target.origin
        panel.setFrameOrigin(position)
        isTracking = true
        startMonitors()
        startDisplayLink()
    }

    func stop() {
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
        mouseMonitors = []
        displayLink?.invalidate()
        displayLink = nil
        panel = nil
        sizeProvider = nil
        caretProvider = { nil }
        isTracking = false
    }

    /// For `zeus debug` and tests: the frame the tracked panel would take right now, without
    /// needing a real mouse move first.
    func currentFrame() -> CGRect? {
        guard let panel else { return nil }
        syncPanelToPointer()
        return panel.frame
    }

    /// Snap the tracked panel to the pointer now (for debug/E2E and after synthetic moves).
    private func syncPanelToPointer() {
        guard let panel else { return }
        let target = targetFrame().origin
        position = Motion.reduced ? target : SpringFollow.step(current: position, target: target, dt: 1.0 / 60)
        panel.setFrameOrigin(position)
    }

    private func targetFrame() -> CGRect {
        let size = sizeProvider?() ?? .zero
        let cursor = NSEvent.mouseLocation
        let screens = NSScreen.screens.map(\.visibleFrame)
        let screenFrame = CursorAnchor.screenFrame(containing: cursor, screens: screens, main: NSScreen.main?.visibleFrame)
        return CursorAnchor.frame(cursor: cursor, size: size, screenFrame: screenFrame, caretRect: caretProvider())
    }

    private func startMonitors() {
        let wake: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.wake() } }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: wake) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { event in wake(event); return event }) {
            mouseMonitors.append(local)
        }
    }

    private func wake() {
        guard let link = displayLink, link.isPaused else { return }
        lastTimestamp = 0
        link.isPaused = false
    }

    private func startDisplayLink() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Coalesced to the display refresh (the display link), never a separate free-running timer.
    @objc private func tick(_ link: CADisplayLink) {
        guard let panel else { link.invalidate(); displayLink = nil; return }
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? 1.0 / 60 : min(now - lastTimestamp, 0.05)
        lastTimestamp = now
        let target = targetFrame().origin
        let next = Motion.reduced ? target : SpringFollow.step(current: position, target: target, dt: dt)
        position = next
        panel.setFrameOrigin(next)
        let settled = Motion.reduced || hypot(next.x - target.x, next.y - target.y) < 0.75
        link.isPaused = settled
    }
}

/// Best-effort caret rect in global (AppKit, bottom-left-origin) screen coordinates, via the
/// Accessibility API. Returns nil the instant anything is missing or fails -- no Accessibility
/// access, no focused element, no text caret, or any other reason -- so a caller can simply treat
/// nil as "no caret to avoid" rather than guard every step itself. Never raises, never prompts.
enum CaretLocator {
    static func currentCaretRect() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return nil }
        let element = focused as! AXUIElement
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef else { return nil }
        var boundsRef: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsRef)
        guard status == .success, let boundsValue = boundsRef else { return nil }
        guard CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        let boxed = unsafeBitCast(boundsValue, to: AXValue.self)
        guard AXValueGetValue(boxed, .cgRect, &rect) else { return nil }
        // AX bounds are in top-left-origin (Quartz display) coordinates, relative to the main
        // screen's top edge; AppKit's own coordinate space has the *main* screen's bottom-left
        // as (0, 0). The flip below is exact on the main screen and a reasonable best-effort
        // approximation on a secondary display -- either way this is only used to avoid covering
        // a caret by a margin, not a correctness-critical calculation.
        let mainHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
        let flippedY = mainHeight - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: flippedY, width: max(rect.width, 1), height: max(rect.height, 1))
    }
}
