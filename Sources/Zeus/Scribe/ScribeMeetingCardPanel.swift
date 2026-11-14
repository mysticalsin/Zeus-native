import AppKit
import SwiftUI
import ZeusCore

/// Puts a `ScribeMeetingCard` on screen. The caller hands over the whole card each time; there is no show,
/// hide or update call besides this one.
@MainActor
protocol ScribeMeetingCardRendering: AnyObject {
    func render(_ card: ScribeMeetingCard)
}

/// Hosting view for the Scribe meeting cards. The cards sit in non-activating panels that are almost never key
/// (the person is in their call app when a meeting starts). Without `acceptsFirstMouse` AppKit spends the first
/// click on making the panel key and the button never sees it: that was the "I clicked and nothing happened".
/// It also reports the pointer entering and leaving, so a card never times out under the hand about to tap it.
final class ScribeCardHostingView<Content: View>: NSHostingView<Content> {
    var onPointer: (@MainActor (Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onPointer?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointer?(false)
    }
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
    /// Every tap hands over the card the person saw, so the machine reads it against the card it holds now.
    struct Actions {
        var primary: (ScribeMeetingCard) -> Void = { _ in }
        var cancel: (ScribeMeetingCard) -> Void = { _ in }
        var dismiss: (ScribeMeetingCard) -> Void = { _ in }
        var pointer: (Bool) -> Void = { _ in }
    }

    /// Moves the panel's alpha to `alpha`, then calls `completion`. A test replaces it to decide when a fade ends.
    typealias Fade = @MainActor (NSPanel, CGFloat, (@MainActor @Sendable () -> Void)?) -> Void

    private static let margin: CGFloat = 16
    fileprivate static let fadeDuration: TimeInterval = 0.2

    private let actions: Actions
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private let visibleFrame: () -> CGRect
    private let fade: Fade
    private(set) var window: NSPanel?
    private var host: ScribeCardHostingView<ScribeMeetingCardView>?
    /// Counts renders, so a fade-out that ends after a later render knows it has been overtaken.
    private var generation = 0

    var isOnScreen: Bool { window?.isVisible ?? false }
    var hostedView: ScribeMeetingCardView? { host?.rootView }
    var drawnCard: ScribeMeetingCard { host?.rootView.card ?? .hidden }

    init(actions: Actions,
         now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         visibleFrame: @escaping () -> CGRect = {
             (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
         },
         fade: Fade? = nil) {
        self.actions = actions
        self.now = now
        self.uptime = uptime
        self.visibleFrame = visibleFrame
        self.fade = fade ?? Self.animatedFade
    }

    func render(_ card: ScribeMeetingCard) {
        generation += 1
        guard card != .hidden else {
            guard let window, let host, window.isVisible else { return }
            let latest = generation
            // The buttons are still drawn while the card fades, so they must not answer a tap.
            window.ignoresMouseEvents = true
            fade(window, 0) { [self] in
                // A later render has the say: it has either raised the card again or will take it down itself.
                guard generation == latest else { return }
                window.orderOut(nil)
                // The next card appears from nothing, so its entrance plays again.
                host.rootView = view(.hidden)
            }
            return
        }
        let (panel, host) = ensurePanel()
        let wasVisible = panel.isVisible
        panel.ignoresMouseEvents = false
        host.rootView = view(card)
        layout(panel, host)
        if wasVisible {
            fade(panel, 1, nil)
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

    private static let animatedFade: Fade = { panel, alpha, completion in
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduced ? AlertMotion.reducedFade : ScribeMeetingCardPanel.fadeDuration
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
        if let panel = window, let host { return (panel, host) }
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
        window = panel
        self.host = host
        return (panel, host)
    }
}
