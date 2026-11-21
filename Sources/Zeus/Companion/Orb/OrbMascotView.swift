import AppKit
import MetalKit
import SwiftUI
import ZeusCore

/// The optional particle mascot. It draws inside the buddy overlay that already exists.
/// A Mac without a Metal device shows a still disc. That disc is not the simulation.
struct OrbMascotView: NSViewRepresentable {
    var visualState: OrbVisualState
    var reduceMotion: Bool
    var paused: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = try? OrbMetalRenderer(device: device, bands: OrbPlaybackMeter.shared) else {
            return StillDisc()
        }
        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.framebufferOnly = true
        view.isOpaque = false
        view.layer?.isOpaque = false
        view.preferredFramesPerSecond = OrbRedrawPolicy.activeFramesPerSecond
        renderer.setVisualState(visualState)
        renderer.setReduceMotion(reduceMotion)
        view.delegate = renderer
        let coordinator = context.coordinator
        coordinator.renderer = renderer
        coordinator.holdStill = holdStill
        coordinator.apply(view)
        renderer.onPipelinesReady = { [weak view, weak coordinator] in
            guard let view, let coordinator else { return }
            coordinator.apply(view)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.renderer?.setVisualState(visualState)
        context.coordinator.renderer?.setReduceMotion(reduceMotion)
        context.coordinator.holdStill = holdStill
        if let metal = view as? MTKView { context.coordinator.apply(metal) }
    }

    /// Caller pause, the quiet pose, or Reduce Motion. The Bool is the system setting the caller read.
    private var holdStill: Bool {
        paused || OrbRedrawPolicy.pausesRedraw(visualState: visualState, reduceMotion: reduceMotion)
    }

    final class Coordinator {
        var renderer: OrbMetalRenderer?
        var holdStill = true

        func apply(_ view: MTKView) {
            view.preferredFramesPerSecond = OrbRedrawPolicy.activeFramesPerSecond
            view.isPaused = holdStill
            view.enableSetNeedsDisplay = holdStill
            if holdStill { view.needsDisplay = true }
        }
    }
}

/// Stand-in when Metal is absent. It does not step the simulation.
private final class StillDisc: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = CGColor(red: 5.0 / 255, green: 5.0 / 255, blue: 8.0 / 255, alpha: 0.85)
        layer?.cornerRadius = 28
    }

    required init?(coder: NSCoder) { nil }
}
