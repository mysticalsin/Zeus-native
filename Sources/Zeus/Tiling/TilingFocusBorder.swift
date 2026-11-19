import AppKit
import SwiftUI
import ZeusCore

/// The thin ring around the window the tiling keys act on.
///
/// One panel, reused: click-through, borderless and non-activating, never key or main, on every Space, at the
/// floating level so it stays below the notch window. It draws one static stroke, so it has no clock and costs
/// nothing between changes. It exists only while it is showing: hiding closes the panel. It follows the screen
/// share policy like every other Zeus overlay, and `ZeusWindowSharing.refresh` reaches it.
@MainActor
final class TilingFocusBorder {
    static let shared = TilingFocusBorder()

    /// How far the panel reaches beyond the window it marks, in points. The stroke sits in that margin.
    static let outset: CGFloat = 4
    static let lineWidth: CGFloat = 2
    static let cornerRadius: CGFloat = 12
    static let level = NSWindow.Level.floating

    private var panel: NSPanel?
    private var lastVisibleInShare = false

    /// The panel while it is showing; empty otherwise. For tests.
    var ownedWindows: [NSWindow] { panel.map { [$0] } ?? [] }

    /// Where the panel goes for `target`: the window's frame in AppKit coordinates, grown by the margin.
    static func panelFrame(for target: TilingRingTarget) -> CGRect {
        let frame = target.display.toAppKit(target.frame)
        return CGRect(x: frame.x - outset, y: frame.y - outset, width: frame.width + 2 * outset, height: frame.height + 2 * outset)
    }

    func show(_ target: TilingRingTarget) {
        guard !TopBarStyle.isSnapshot, !NSScreen.screens.isEmpty else {
            hide()
            return
        }
        let isNew = panel == nil
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(Self.panelFrame(for: target), display: false)
        if isNew, !Motion.reduced {
            // A short fade the first time it appears; moving to another window is immediate.
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
    }

    func applyScreenSharePolicy(visibleInShare: Bool) {
        lastVisibleInShare = visibleInShare
        if let panel { ZeusWindowSharing.apply(to: panel, visibleInShare: visibleInShare, surface: .zeusStandard) }
    }

    /// For `zeus debug animate`: shown to capture for a moment, then back to the policy.
    func boostCaptureVisibility(for seconds: TimeInterval) {
        panel?.sharingType = .readOnly
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applyScreenSharePolicy(visibleInShare: self.lastVisibleInShare)
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = Self.level
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: TilingRingView())
        ZeusWindowSharing.apply(to: panel, visibleInShare: lastVisibleInShare, surface: .zeusStandard)
        return panel
    }
}

/// One rounded stroke just outside the window, with a soft wider line under it unless Reduce Transparency is on.
private struct TilingRingView: View {
    var body: some View {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        Canvas { context, size in
            let margin = TilingFocusBorder.outset - TilingFocusBorder.lineWidth / 2
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin)
            guard rect.width > 1, rect.height > 1 else { return }
            let path = Path(roundedRect: rect, cornerRadius: TilingFocusBorder.cornerRadius, style: .continuous)
            if !reduceTransparency {
                context.stroke(path, with: .color(Theme.accent.opacity(0.22)), lineWidth: TilingFocusBorder.lineWidth * 2.5)
            }
            context.stroke(path, with: .color(Theme.accent), lineWidth: TilingFocusBorder.lineWidth)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
