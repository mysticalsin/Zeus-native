import AppKit
import SwiftUI
import ZeusCore

/// Puts a `ScribeMeetingCard` on screen. The caller hands over the whole card each time; there is no show,
/// hide or update call besides this one.
@MainActor
protocol ScribeMeetingCardRendering: AnyObject {
    func render(_ card: ScribeMeetingCard)
}

/// Same rule as the other Scribe cards: it never takes the keyboard from what the person is typing in. It can
/// become key, so Return and Escape work once the person has clicked it.
private final class ScribeMeetingCardWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The one non-activating panel for the meeting card, top right of the screen. `render` shows, updates or takes
/// the card down; nothing else makes the panel appear or leave.
@MainActor
final class ScribeMeetingCardPanel: ScribeMeetingCardRendering {
    struct Actions {
        var primary: () -> Void = {}
        var cancel: () -> Void = {}
        var dismiss: () -> Void = {}
        var pointer: (Bool) -> Void = { _ in }
    }

    private static let margin: CGFloat = 16
    private static let fade: TimeInterval = 0.2

    private let actions: Actions
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private let visibleFrame: () -> CGRect
    private var panel: NSPanel?
    private var host: ScribeCardHostingView<ScribeMeetingCardView>?

    init(actions: Actions,
         now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         visibleFrame: @escaping () -> CGRect = {
             (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
         }) {
        self.actions = actions
        self.now = now
        self.uptime = uptime
        self.visibleFrame = visibleFrame
    }

    func render(_ card: ScribeMeetingCard) {
        guard card != .hidden else {
            guard let panel, let host, panel.isVisible else { return }
            // Fade, then leave; a card that arrives meanwhile has raised the alpha again, so it stays.
            fade(panel, to: 0) { [weak self] in
                guard panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
                // The next card appears from nothing, so its entrance plays again.
                host.rootView = self?.view(.hidden) ?? host.rootView
            }
            return
        }
        let (panel, host) = ensurePanel()
        let wasVisible = panel.isVisible
        host.rootView = view(card)
        layout(panel, host)
        if wasVisible {
            fade(panel, to: 1)
        } else {
            panel.alphaValue = 1
            // Front without activating Zeus: whatever the person is typing in keeps the keyboard.
            panel.orderFrontRegardless()
        }
    }

    private func view(_ card: ScribeMeetingCard) -> ScribeMeetingCardView {
        ScribeMeetingCardView(card: card, now: now(), uptime: uptime(),
                              onPrimary: actions.primary, onCancel: actions.cancel,
                              onDismiss: actions.dismiss)
    }

    private func fade(_ panel: NSPanel, to alpha: CGFloat, completion: (@MainActor @Sendable () -> Void)? = nil) {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduced ? AlertMotion.reducedFade : Self.fade
            panel.animator().alphaValue = alpha
        }, completionHandler: {
            MainActor.assumeIsolated { completion?() }
        })
    }

    private func layout(_ panel: NSPanel, _ host: NSView) {
        let size = host.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(ScribeMeetingCardPlacement.origin(size: size, visibleFrame: visibleFrame(),
                                                               margin: Self.margin))
    }

    private func ensurePanel() -> (NSPanel, ScribeCardHostingView<ScribeMeetingCardView>) {
        if let panel, let host { return (panel, host) }
        let host = ScribeCardHostingView(rootView: view(.hidden))
        host.onPointer = { [weak self] inside in self?.actions.pointer(inside) }
        let panel = ScribeMeetingCardWindow(
            contentRect: NSRect(x: 0, y: 0, width: ScribeMeetingCardView.width, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.contentView = host
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.panel = panel
        self.host = host
        return (panel, host)
    }
}
