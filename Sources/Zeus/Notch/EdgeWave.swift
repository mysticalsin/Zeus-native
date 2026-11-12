import SwiftUI
import AppKit
import ZeusCore

/// The "light wave to the screen edges": a click-through overlay over every screen on which two
/// fronts of light leave the top centre, run round the screen edge in both directions and meet at the bottom.
/// It joins every Space, never takes the mouse, and is left out of screenshots and screen sharing
/// unless QA capture boost is active.
@MainActor
final class EdgeWaveController {
    static let shared = EdgeWaveController()
    private var panels: [NSPanel] = []
    private var closing: Task<Void, Never>?
    private var lastVisibleInShare = false
    static let duration: TimeInterval = 1.6

    func applyScreenSharePolicy(visibleInShare: Bool) {
        lastVisibleInShare = visibleInShare
        for panel in panels {
            ZeusWindowSharing.apply(to: panel, visibleInShare: visibleInShare, surface: .zeusStandard)
        }
    }

    func boostCaptureVisibility(for seconds: TimeInterval) {
        for panel in panels { panel.sharingType = .readOnly }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self else { return }
            self.applyScreenSharePolicy(visibleInShare: self.lastVisibleInShare)
        }
    }

    func play(tint: NotchLightTint, ignoreSettings: Bool = false) {
        guard !TopBarStyle.isSnapshot else { return }
        _ = ignoreSettings
        closing?.cancel()
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        if panels.count != screens.count {
            panels.forEach { $0.orderOut(nil) }
            panels = screens.map { _ in makePanel() }
        }
        let started = Date()
        for (panel, screen) in zip(panels, screens) {
            panel.setFrame(screen.frame, display: false)
            panel.contentView = NSHostingView(
                rootView: EdgeWaveView(tint: tint, started: started, duration: Self.duration, reduceMotion: Motion.reduced))
            panel.orderFrontRegardless()
        }
        closing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.duration + 0.15))
            guard !Task.isCancelled else { return }
            self?.panels.forEach { $0.orderOut(nil); $0.contentView = nil }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: GlanceTopBar.windowLayer + 2)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ZeusWindowSharing.apply(to: panel, visibleInShare: lastVisibleInShare, surface: .zeusStandard)
        return panel
    }
}

struct EdgeWaveView: View {
    let tint: NotchLightTint
    let started: Date
    let duration: TimeInterval
    let reduceMotion: Bool

    var body: some View {
        EdgeLightClock(reduceMotion: reduceMotion) { context in
            let p = max(0, min(1, context.date.timeIntervalSince(started) / duration))
            Canvas { ctx, size in
                EdgeWaveView.draw(&ctx, size: size, progress: p, color: tint.color, reduceMotion: reduceMotion)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The right half of the screen edge, from the top centre round to the bottom centre. It hugs the
    /// physical edge; the top bar's drop never moves it (`ScreenEdgeOutline`).
    static func halfPerimeter(_ size: CGSize) -> Path {
        let o = ScreenEdgeOutline(width: Double(size.width), height: Double(size.height))
        let cx = CGFloat(o.centerX), t = CGFloat(o.top), r = CGFloat(o.right), b = CGFloat(o.bottom), radius = CGFloat(o.radius)
        var p = Path()
        p.move(to: CGPoint(x: cx, y: t))
        p.addLine(to: CGPoint(x: r - radius, y: t))
        p.addQuadCurve(to: CGPoint(x: r, y: t + radius), control: CGPoint(x: r, y: t))
        p.addLine(to: CGPoint(x: r, y: b - radius))
        p.addQuadCurve(to: CGPoint(x: r - radius, y: b), control: CGPoint(x: r, y: b))
        p.addLine(to: CGPoint(x: cx, y: b))
        return p
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, progress p: Double, color: Color, reduceMotion: Bool) {
        let fronts = EdgeWaveMath.fronts(progress: p)
        guard fronts.opacity > 0.01 else { return }
        let outline = Polyline(path: halfPerimeter(size))
        // Reduce Motion: the whole edge fades in and out together instead of travelling.
        let lit = reduceMotion ? outline : outline.slice(from: fronts.tail, to: fronts.head)
        var paint = HaloPaint(color: color, opacity: fronts.opacity * (reduceMotion ? 0.7 : 1), line: 3, bloom: 2.4, scale: 1)
        paint.reduceMotion = reduceMotion
        for mirrored in [false, true] {
            var side = ctx
            if mirrored { side.translateBy(x: size.width, y: 0); side.scaleBy(x: -1, y: 1) }
            HaloRenderer.draw(.classic, line: lit, in: &side, paint: paint)
            // A broad wash just inside the edge.
            var wash = side
            wash.addFilter(.blur(radius: 26))
            wash.stroke(lit.path, with: .color(color.opacity(fronts.opacity * 0.22)), style: .init(lineWidth: 40, lineCap: .round, lineJoin: .round))
        }
    }
}

/// The clock both screen-edge lights (this wave and `ScreenEdgeGlowController`'s level glow) draw from.
/// In motion it follows the display (`DisplaySynchronizedView`: every refresh, 120 Hz on ProMotion, in
/// step with vsync), so the travelling light no longer judders the way a 60 Hz run-loop timer beating
/// against the display did. Reduce Motion keeps the slow `TickingView` fade, which needs no display link.
struct EdgeLightClock<Content: View>: View {
    let reduceMotion: Bool
    /// The Reduce Motion fade's tick.
    var reducedInterval: TimeInterval = 0.1
    @ViewBuilder let content: (TickContext) -> Content

    var body: some View {
        if reduceMotion {
            TickingView(interval: reducedInterval, content: content)
        } else {
            DisplaySynchronizedView(content: content)
        }
    }
}
