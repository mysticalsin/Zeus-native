import AppKit
import SwiftUI
import ZeusCore

/// Passive desktop drawing only. It never owns input, requests Accessibility access, starts
/// capture, or sends actions to another app. Chat owns the separate interactive controls.
@MainActor
final class ExplanationOverlay {
    private var panels: [UInt32: ExplanationDrawingPanel] = [:]
    private var invalidationObservation: ExplanationScreenObservation?
    private var captureID: UUID?
    private var visibleInShare = false
    /// Chat annotations sit at `.floating`. The pointing overlay must stay above open menus.
    var windowLevel: NSWindow.Level = .floating

    var isVisible: Bool { panels.values.contains(where: \.isVisible) }
    var displayIDs: Set<UInt32> { Set(panels.keys) }
    /// Own-process lifecycle fixtures inspect window policy without any capture or input.
    var ownedWindows: [NSWindow] { Array(panels.values) }

    isolated deinit {
        invalidationObservation?.cancel()
        for panel in panels.values { panel.orderOut(nil); panel.contentView = nil; panel.close() }
    }

    @discardableResult
    func present(scene: ExplanationScene, context: ExplanationScreenContext,
                 registry: ExplanationRegistry = .empty, reduceMotion: Bool = true) -> Bool {
        context.recheckLease()
        guard let capture = context.annotationContext,
              capture.isCurrent(captureID: scene.captureID),
              let mapping = Self.panelTransform(capture) else { hide(); return false }
        let display = capture.currentDisplay
        let size = CGSize(width: display.frame.width, height: display.frame.height)
        var passiveScene = scene
        passiveScene.objects = scene.objects.filter { $0.value.space == .capture && $0.value.captureID == capture.geometry.captureID }
        guard !passiveScene.objects.isEmpty else { hide(); return false }
        let layout = ExplanationCanvasLayout(scene: passiveScene, size: size, registry: registry,
            captureContext: capture, viewportID: UUID(), reduceMotion: reduceMotion, captureTransform: mapping)
        guard layout.isValid else { hide(); return false }

        let frame = NSRect(x: display.frame.x, y: display.frame.y, width: size.width, height: size.height)
        let surface = AnyView(ExplanationCanvasArtwork(layout: layout)
            .frame(width: size.width, height: size.height).clipped()
            .allowsHitTesting(false).accessibilityHidden(true))
        if captureID == capture.geometry.captureID,
           let panel = panels[display.displayID], panel.frame == frame,
           let host = panel.contentView as? NSHostingView<AnyView> {
            host.rootView = surface
            return true
        }
        hide()
        let panel = ExplanationDrawingPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = windowLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ZeusWindowSharing.apply(to: panel, visibleInShare: visibleInShare, surface: .zeusStandard)
        let host = NSHostingView(rootView: surface)
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(frame, display: false)
        panels[display.displayID] = panel
        captureID = capture.geometry.captureID
        invalidationObservation = context.observeInvalidation { [weak self] _ in self?.hide() }
        panel.orderFrontRegardless() // Nonactivating panel; never makeKey or activate another app.
        return true
    }

    func hide() {
        invalidationObservation?.cancel(); invalidationObservation = nil
        for panel in panels.values { panel.orderOut(nil); panel.contentView = nil; panel.close() }
        panels.removeAll()
        captureID = nil
    }

    func applyScreenSharePolicy(visibleInShare: Bool) {
        self.visibleInShare = visibleInShare
        for panel in panels.values {
            ZeusWindowSharing.apply(to: panel, visibleInShare: visibleInShare, surface: .zeusStandard)
        }
    }

    /// Delivered-image pixels -> this panel's top-left logical points. Each axis keeps the
    /// actual crop/resize ratio; the Core geometry supplies the corresponding AppKit inverse.
    static func panelTransform(_ context: ExplanationCaptureContext) -> ExplanationCaptureDrawingTransform? {
        guard context.isCurrent(captureID: context.geometry.captureID) else { return nil }
        let g = context.geometry, frame = context.currentDisplay.frame
        let x = g.crop.x * frame.width / g.fullImageSize.width
        let y = g.crop.y * frame.height / g.fullImageSize.height
        let width = g.crop.width * frame.width / g.fullImageSize.width
        let height = g.crop.height * frame.height / g.fullImageSize.height
        return ExplanationCaptureDrawingTransform(context: context,
            affine: CGAffineTransform(a: width / g.imageSize.width, b: 0, c: 0,
                                      d: height / g.imageSize.height, tx: x, ty: y),
            clip: CGRect(x: x, y: y, width: width, height: height))
    }
}

private final class ExplanationDrawingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
