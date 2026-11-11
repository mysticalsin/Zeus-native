import AppKit
import ZeusCore

/// Show-me: hold the left Command key on its own, then draw or circle anything on screen.
/// A transparent overlay catches the stroke; on release ZEUS takes a screenshot, marks the
/// region on it and answers (or acts) about that spot. A plain Command-click passes through.
@MainActor
final class AnnotationController {
    static let shared = AnnotationController()
    static let enabledKey = "annotate.enabled"
    /// Hold this long before the overlay takes the mouse, so quick shortcuts never see it.
    static let holdDelay: Duration = .milliseconds(350)

    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var armTask: Task<Void, Never>?
    private var drawing = false
    private var current: [CGPoint] = []
    private var strokes: [[CGPoint]] = []
    /// Asks the brain about the marked spot: prompt plus the marked screenshots.
    var onMark: ((String, [ScreenShot]) -> Void)?

    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    func start() {
        AccessibilityGate.whenTrusted { AnnotationController.shared.startMonitors() }
    }

    private func startMonitors() {
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let leftCommand = event.keyCode == 55
            MainActor.assumeIsolated { AnnotationController.shared.flags(flags, leftCommand: leftCommand) }
        }
        // Any other key while Command is down is a shortcut, not a drawing.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated { AnnotationController.shared.clearMark() }
                return
            }
            MainActor.assumeIsolated { AnnotationController.shared.disarm() }
        }
    }

    func clearMark() {
        armTask?.cancel()
        MarkModel.shared.strokes = []
        if drawing { disarm() } else { MarkOverlay.shared.hide() }
        NSLog("[ZEUS] show-me: cleared")
    }

    private func flags(_ flags: NSEvent.ModifierFlags, leftCommand: Bool) {
        guard enabled else { return }
        if flags == .command, leftCommand {
            armTask?.cancel()
            armTask = Task { @MainActor in
                try? await Task.sleep(for: Self.holdDelay)
                guard !Task.isCancelled, NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      NSEvent.pressedMouseButtons == 0 else { return }
                self.arm()
            }
        } else if !flags.contains(.command) {
            armTask?.cancel()
            if drawing { finish() }
        } else {
            disarm()
        }
    }

    private func arm() {
        guard !drawing, !DriveController.shared.isDriving else { return }
        drawing = true
        strokes = []
        current = []
        MarkModel.shared.strokes = []
        MarkOverlay.shared.onMouse = { type, point in
            MainActor.assumeIsolated { AnnotationController.shared.mouse(type, at: point) }
        }
        MarkOverlay.shared.show(capturingMouse: true)
        NSLog("[ZEUS] show-me: armed")
    }

    func disarm() {
        armTask?.cancel()
        guard drawing else { return }
        drawing = false
        MarkModel.shared.strokes = []
        MarkOverlay.shared.hide()
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint) {
        switch type {
        case .leftMouseDown: current = [point]
        case .leftMouseDragged:
            if let last = current.last, hypot(point.x - last.x, point.y - last.y) < 2 { return }
            current.append(point)
        default:
            current.append(point)
            strokes.append(current)
            current = []
        }
        MarkModel.shared.strokes = strokes + (current.isEmpty ? [] : [current])
    }

    private func finish() {
        let all = strokes.flatMap { $0 } + current
        let main = AnnotationStroke(points: (strokes + [current]).max { $0.count < $1.count } ?? [])
        drawing = false
        MarkOverlay.shared.hide()
        guard !all.isEmpty else { MarkModel.shared.strokes = []; return }
        // A Command-click with no drag was meant for the app underneath: hand it back.
        if strokes.count == 1, main.shape == .spot, let p = all.first {
            MarkModel.shared.strokes = []
            NSLog("[ZEUS] show-me: plain Command-click passed through")
            let q = DriveController.quartz(p)
            guard AccessibilityGate.trusted else { return }
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: q, mouseButton: .left)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
            return
        }
        let combined = AnnotationStroke(points: all)
        NSLog("[ZEUS] show-me: %@ stroke, %d points", main.shape.rawValue, all.count)
        Task { @MainActor in
            let shots = await ScreenCapture.captureAll()
            MarkModel.shared.strokes = []
            guard let (prompt, marked) = Self.mark(combined, shape: main.shape, on: shots) else {
                NSLog("[ZEUS] show-me: no screenshot (Screen Recording off)")
                self.onMark?("I marked something on screen but you can't see the screen yet. Tell me to turn on Screen Recording for Zeus.", [])
                return
            }
            self.onMark?(prompt, marked)
        }
    }

    /// The prompt and the shots, with the region outlined in the bolt color on its screen.
    static func mark(_ stroke: AnnotationStroke, shape: AnnotationStroke.Shape, on shots: [ScreenShot]) -> (String, [ScreenShot])? {
        let center = CGPoint(x: stroke.bounds.midX, y: stroke.bounds.midY)
        guard let index = shots.firstIndex(where: { $0.displayFrame.contains(center) }) ?? (shots.isEmpty ? nil : 0) else { return nil }
        let shot = shots[index]
        let region = stroke.region(in: shot.displayFrame)
        let pixels = AnnotationStroke.pixelRect(region, displayFrame: shot.displayFrame,
                                                pixelWidth: shot.pixelWidth, pixelHeight: shot.pixelHeight)
        var out = shots
        if let cropped = AnnotationCrop.croppedShot(from: shot, pixelRect: pixels) {
            return (stroke.prompt(question: nil, pixels: pixels, screen: index + 1, shape: shape), [cropped])
        }
        if let outlined = outline(shot, pixels: pixels) { out[index] = outlined }
        return (stroke.prompt(question: nil, pixels: pixels, screen: index + 1, shape: shape), out)
    }

    static func outline(_ shot: ScreenShot, pixels: CGRect) -> ScreenShot? {
        guard let source = NSBitmapImageRep(data: shot.jpegData)?.cgImage,
              let context = CGContext(data: nil, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let size = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        context.draw(source, in: size)
        context.setStrokeColor(NSColor(Theme.bolt).cgColor)
        context.setLineWidth(4)
        // CGContext is bottom-left; pixels are top-left.
        context.stroke(CGRect(x: pixels.minX, y: CGFloat(source.height) - pixels.maxY, width: pixels.width, height: pixels.height))
        guard let image = context.makeImage(),
              let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        return ScreenShot(jpegData: jpeg, label: shot.label + " (Zeus outlined the marked spot)", pixelWidth: shot.pixelWidth,
                          pixelHeight: shot.pixelHeight, displayFrame: shot.displayFrame)
    }
}
