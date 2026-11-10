import SwiftUI
import AppKit
import ZeusCore

/// P0 item G: on a volume, brightness or keyboard-backlight change (and mute), a glow runs around
/// every screen's edge and joins the notch at the top, filled to the level. Click-through,
/// borderless, above the menu bar, left out of screenshots and screen sharing, same shape as
/// `EdgeWaveController`'s one-shot wave but level-driven and continuous across repeated key
/// presses (G's math lives in `ZeusCore.ScreenEdgeGlowMath`, mirroring the notch's own H2/H3).
/// Event-driven only: the `TickingView` inside only runs while `state` is active, and the panels
/// are ordered out the moment the fade-out finishes, so idle CPU stays at zero between changes.
@MainActor
final class ScreenEdgeGlowController {
    static let shared = ScreenEdgeGlowController()

    private var panels: [NSPanel] = []
    fileprivate var state: ScreenEdgeGlowState?
    private var hideTask: Task<Void, Never>?
    private var lastVisibleInShare = false

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

    /// Called alongside `TopBarModel.presentSystemHUD` for every real HUD change. `value`/`muted`
    /// are the same inputs the notch's own light already uses.
    func present(kind: SystemHUDKind, value: Double, muted: Bool, ignoreSettings: Bool = false) {
        guard !TopBarStyle.isSnapshot else { return }
        if !ignoreSettings, !SettingsStore.shared.bool("lights.hud.screenEdge") { return }
        let now = Date()
        let target = muted ? 0 : max(0, min(1, value))
        let from = ScreenEdgeGlowMath.startLevel(previous: state, now: now, reduceMotion: Motion.reduced, fallback: target)
        state = ScreenEdgeGlowState(kind: kind, fromLevel: from, toLevel: target, muted: muted, changedAt: now)
        ensurePanelsVisible()
        scheduleHide()
    }

    /// `zeus debug animate volume|brightness|keyboard|mute`: a demo change with no real hardware.
    func presentDemo(_ kind: SystemHUDKind, muted: Bool = false) {
        present(kind: kind, value: kind == .keyboardBacklight ? 0.6 : 0.55, muted: muted)
    }

    /// For `zeus debug hud-state`/tests: the frame that would be drawn right now, or nil if idle.
    func currentFrame(now: Date = Date()) -> ScreenEdgeGlowFrame? {
        guard let state else { return nil }
        let frame = ScreenEdgeGlowMath.frame(state, now: now, reduceMotion: Motion.reduced)
        return frame.isActive ? frame : nil
    }

    private func ensurePanelsVisible() {
        let screens = NSScreen.screens
        if panels.count != screens.count {
            panels.forEach { $0.orderOut(nil) }
            panels = screens.map { _ in makePanel() }
        }
        for (panel, screen) in zip(panels, screens) {
            panel.setFrame(screen.frame, display: false)
            if panel.contentView == nil {
                panel.contentView = NSHostingView(rootView: ScreenEdgeGlowView(controller: self))
            }
            panel.orderFrontRegardless()
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ScreenEdgeGlowMath.totalDuration + 0.1))
            guard !Task.isCancelled, let self else { return }
            self.panels.forEach { $0.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ZeusWindowSharing.apply(to: panel, visibleInShare: lastVisibleInShare, surface: .zeusStandard)
        return panel
    }
}

/// Reads `controller.state` on every tick but only while something is active (`ScreenEdgeGlowMath`
/// reports `isActive`); `TickingView` itself stops ticking once this view is removed or hidden.
private struct ScreenEdgeGlowView: View {
    let controller: ScreenEdgeGlowController

    private var active: Bool { controller.currentFrame() != nil }

    var body: some View {
        if active {
            TickingView(interval: Motion.reduced ? 1.0 / 15 : 1.0 / 60) { context in
                content(at: context.date)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        if let state = controller.state {
            let frame = ScreenEdgeGlowMath.frame(state, now: now, reduceMotion: Motion.reduced)
            Canvas { ctx, size in
                guard frame.opacity > 0.003 else { return }
                ScreenEdgeGlowView.draw(&ctx, size: size, level: frame.level, opacity: frame.opacity,
                                        color: color(for: state.kind),
                                        reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
            }
        }
    }

    /// Same colour the notch's own `.hudLevel` light uses for each control (Notch/NotchLights.swift).
    private func color(for kind: SystemHUDKind) -> Color {
        switch kind {
        case .volume: Theme.bolt
        case .brightness: Theme.sky
        case .keyboardBacklight: Color(red: 0.66, green: 0.45, blue: 1)
        }
    }

    /// The edge is lit from the top centre both ways, out to a fraction `level` of the half
    /// perimeter -- the same geometry `EdgeWaveView` already uses for its one-shot wave, reused
    /// here as a static fill instead of a travelling front.
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, level: Double, opacity: Double, color: Color, reduceTransparency: Bool) {
        guard size.width > 1, size.height > 1 else { return }
        let outline = Polyline(path: EdgeWaveView.halfPerimeter(size))
        let lit = outline.slice(from: 0, to: max(0.0015, level))
        for mirrored in [false, true] {
            var side = ctx
            if mirrored { side.translateBy(x: size.width, y: 0); side.scaleBy(x: -1, y: 1) }
            side.stroke(lit.path, with: .color(color.opacity(opacity * 0.95)), style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round))
            // Reduce Transparency: a plain stroke, no soft blurred wash.
            guard !reduceTransparency else { continue }
            var wash = side
            wash.addFilter(.blur(radius: 16))
            wash.stroke(lit.path, with: .color(color.opacity(opacity * 0.3)), style: .init(lineWidth: 24, lineCap: .round, lineJoin: .round))
        }
    }
}
