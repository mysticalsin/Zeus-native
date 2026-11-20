import AppKit
import SwiftUI
import ZeusCore

/// What the screen-wide overlays draw: the stroke you are drawing (show-me) and the trail of
/// the cursor while ZEUS drives. Global AppKit points.
@MainActor @Observable
final class MarkModel {
    static let shared = MarkModel()
    var strokes: [[CGPoint]] = []
    var trail: [CGPoint] = []
    var caption = ""
    /// Ink colour for the pointing trail. nil uses the Zeus accent.
    var inkColor: Color?
    /// Numbered marks in global points. A mark whose display is gone is removed on the next rebuild.
    var pins: [MarkPin] = []
}

/// One transparent, click-through panel per screen, above everything, excluded from capture.
@MainActor
final class MarkOverlay {
    static let shared = MarkOverlay()
    private var panels: [NSPanel] = []
    private var panelsByID: [String: NSPanel] = [:]
    private var screenObserver: NSObjectProtocol?
    private var announcedLabels: [String] = []
    private(set) var capturesMouse = false
    /// The panels, for own-process window-policy checks.
    var ownedWindows: [NSWindow] { panels }
    private var lastVisibleInShare = false

    func applyScreenSharePolicy(visibleInShare: Bool) {
        lastVisibleInShare = visibleInShare
        for panel in panels {
            ZeusWindowSharing.apply(to: panel, visibleInShare: visibleInShare, surface: .zeusStandard)
        }
    }
    /// Called with global points while the overlay captures the mouse (show-me drawing).
    var onMouse: ((NSEvent.EventType, CGPoint) -> Void)?

    private init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    func show(capturingMouse: Bool) {
        if panels.isEmpty { rebuild() }
        capturesMouse = capturingMouse
        for panel in panels {
            panel.ignoresMouseEvents = !capturingMouse
            panel.orderFrontRegardless()
        }
        if capturingMouse { NSCursor.crosshair.push() }
    }

    func hide() {
        if capturesMouse { NSCursor.pop() }
        capturesMouse = false
        panels.forEach { $0.orderOut(nil) }
        panels = []
        panelsByID = [:]
        announcedLabels = []
    }

    private func screensChanged() {
        guard !panels.isEmpty else { return }
        rebuild()
        for panel in panels {
            panel.ignoresMouseEvents = !capturesMouse
            panel.orderFrontRegardless()
        }
    }

    /// One panel per display. An existing panel for a display that is still attached is moved, not replaced.
    private func rebuild() {
        let attached = NSScreen.screens
        let markScreens = attached.map { MarkScreen(id: Self.screenID($0), frame: $0.frame) }
        let placed = MarkLayout { markScreens }.place(MarkModel.shared.pins)
        let kept = Set(placed.map { "\($0.number)\u{1f}\($0.title)" })
        MarkModel.shared.pins.removeAll { !kept.contains("\($0.number)\u{1f}\($0.title)") }

        var next: [String: NSPanel] = [:]
        for screen in attached {
            let id = Self.screenID(screen)
            let panel = panelsByID[id] ?? makePanel(frame: screen.frame)
            panel.setFrame(screen.frame, display: false)
            installCanvas(on: panel, screen: MarkScreen(id: id, frame: screen.frame))
            next[id] = panel
        }
        for (id, panel) in panelsByID where next[id] == nil { panel.orderOut(nil) }
        panelsByID = next
        panels = attached.compactMap { next[Self.screenID($0)] }
        announce(placed)
    }

    private static func screenID(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        let frame = screen.frame
        return "\(frame.origin.x),\(frame.origin.y),\(frame.width),\(frame.height)"
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = MarkPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ZeusWindowSharing.apply(to: panel, visibleInShare: lastVisibleInShare, surface: .zeusStandard)
        let view = MarkCaptureView(frame: CGRect(origin: .zero, size: frame.size))
        view.owner = self
        panel.contentView = view
        return panel
    }

    private func installCanvas(on panel: NSPanel, screen: MarkScreen) {
        guard let view = panel.contentView else { return }
        view.frame = CGRect(origin: .zero, size: screen.frame.size)
        let canvas = MarkCanvas(screen: screen)
        if let host = view.subviews.compactMap({ $0 as? NSHostingView<MarkCanvas> }).first {
            host.frame = view.bounds
            host.rootView = canvas
        } else {
            let host = NSHostingView(rootView: canvas)
            host.frame = view.bounds
            host.autoresizingMask = [.width, .height]
            view.addSubview(host)
        }
        let labels = MarkLayout { [screen] }.place(MarkModel.shared.pins).map(\.accessibilityLabel)
        view.setAccessibilityElement(!labels.isEmpty)
        if labels.isEmpty {
            view.setAccessibilityLabel(nil)
        } else {
            view.setAccessibilityLabel(labels.joined(separator: ", "))
        }
    }

    private func announce(_ placed: [PlacedMark]) {
        let labels = placed.map(\.accessibilityLabel)
        guard labels != announcedLabels, !labels.isEmpty else {
            if labels.isEmpty { announcedLabels = [] }
            return
        }
        announcedLabels = labels
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: labels.joined(separator: ". "),
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    fileprivate func mouse(_ type: NSEvent.EventType) {
        onMouse?(type, NSEvent.mouseLocation)
    }
}

private final class MarkPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class MarkCaptureView: NSView {
    weak var owner: MarkOverlay?
    override func mouseDown(with event: NSEvent) { owner?.mouse(.leftMouseDown) }
    override func mouseDragged(with event: NSEvent) { owner?.mouse(.leftMouseDragged) }
    override func mouseUp(with event: NSEvent) { owner?.mouse(.leftMouseUp) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct MarkCanvas: View {
    let screen: MarkScreen
    private var model: MarkModel { .shared }

    var body: some View {
        Canvas { context, _ in
            func local(_ p: CGPoint) -> CGPoint { MarkLayout.local(p, on: screen) }
            for stroke in model.strokes where stroke.count > 1 {
                var path = Path()
                path.addLines(stroke.map(local))
                let ink = model.inkColor ?? Theme.bolt
                context.stroke(path, with: .color(ink.opacity(0.35)), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            let trail = model.trail
            if trail.count > 1 {
                for i in 1..<trail.count {
                    var segment = Path()
                    segment.move(to: local(trail[i - 1]))
                    segment.addLine(to: local(trail[i]))
                    let fade = Double(i) / Double(trail.count)
                    context.stroke(segment, with: .color(Theme.bolt.opacity(0.15 + 0.75 * fade)),
                                   style: StrokeStyle(lineWidth: 2 + 4 * fade, lineCap: .round))
                }
                if let head = trail.last {
                    let p = local(head)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(Theme.bolt))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MarkLayout { [screen] }.place(model.pins).map(\.accessibilityLabel).joined(separator: ", "))
    }
}
