import AppKit
import SwiftUI

/// What the screen-wide overlays draw: the stroke you are drawing (show-me) and the trail of
/// the cursor while ZEUS drives. Global AppKit points.
@MainActor @Observable
final class MarkModel {
    static let shared = MarkModel()
    var strokes: [[CGPoint]] = []
    var trail: [CGPoint] = []
    var caption = ""
}

/// One transparent, click-through panel per screen, above everything, excluded from capture.
@MainActor
final class MarkOverlay {
    static let shared = MarkOverlay()
    private var panels: [NSPanel] = []
    private(set) var capturesMouse = false
    private var lastVisibleInShare = false

    func applyScreenSharePolicy(visibleInShare: Bool) {
        lastVisibleInShare = visibleInShare
        for panel in panels {
            ZeusWindowSharing.apply(to: panel, visibleInShare: visibleInShare, surface: .zeusStandard)
        }
    }
    /// Called with global points while the overlay captures the mouse (show-me drawing).
    var onMouse: ((NSEvent.EventType, CGPoint) -> Void)?

    func show(capturingMouse: Bool) {
        if panels.isEmpty {
            panels = NSScreen.screens.map { screen in
                let panel = MarkPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.level = .screenSaver
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                ZeusWindowSharing.apply(to: panel, visibleInShare: lastVisibleInShare, surface: .zeusStandard)
                panel.setFrame(screen.frame, display: false)
                let view = MarkCaptureView(frame: CGRect(origin: .zero, size: screen.frame.size))
                view.owner = self
                let host = NSHostingView(rootView: MarkCanvas(origin: screen.frame.origin, height: screen.frame.height))
                host.frame = view.bounds
                host.autoresizingMask = [.width, .height]
                view.addSubview(host)
                panel.contentView = view
                return panel
            }
        }
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
    }

    fileprivate func mouse(_ type: NSEvent.EventType) {
        onMouse?(type, NSEvent.mouseLocation)
    }
}

private final class MarkPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

private final class MarkCaptureView: NSView {
    weak var owner: MarkOverlay?
    override func mouseDown(with event: NSEvent) { owner?.mouse(.leftMouseDown) }
    override func mouseDragged(with event: NSEvent) { owner?.mouse(.leftMouseDragged) }
    override func mouseUp(with event: NSEvent) { owner?.mouse(.leftMouseUp) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct MarkCanvas: View {
    let origin: CGPoint
    let height: CGFloat
    private var model: MarkModel { .shared }

    var body: some View {
        Canvas { context, _ in
            func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - origin.x, y: height - (p.y - origin.y)) }
            for stroke in model.strokes where stroke.count > 1 {
                var path = Path()
                path.addLines(stroke.map(local))
                context.stroke(path, with: .color(Theme.bolt.opacity(0.35)), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                context.stroke(path, with: .color(Theme.bolt), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
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
    }
}
