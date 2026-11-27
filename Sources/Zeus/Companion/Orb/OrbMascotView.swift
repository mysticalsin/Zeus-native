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
        view.isPaused = paused
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 120
        view.layer?.isOpaque = false
        renderer.setVisualState(visualState)
        renderer.setReduceMotion(reduceMotion)
        view.delegate = renderer
        context.coordinator.renderer = renderer
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.renderer?.setVisualState(visualState)
        context.coordinator.renderer?.setReduceMotion(reduceMotion)
        (view as? MTKView)?.isPaused = paused
    }

    final class Coordinator {
        var renderer: OrbMetalRenderer?
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
