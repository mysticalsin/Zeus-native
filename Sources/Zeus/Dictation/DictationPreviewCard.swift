import AppKit
import ApplicationServices
import Observation
import SwiftUI
import ZeusCore

/// The correctable preview: after you speak, the text shows in a glass card by the caret.
/// Edit it, then Return inserts it into the app you were in; Escape throws it away.
@MainActor
final class DictationPreviewCard {
    static let shared = DictationPreviewCard()

    @MainActor @Observable
    final class State {
        var text = ""
        var modeName = ""
    }

    private var panel: PreviewPanel?
    private let state = State()
    private var continuation: CheckedContinuation<String?, Never>?

    /// The text as the person has edited it so far (kept when the card times out).
    var currentText: String { state.text }

    /// Waits for the person: the edited text, or nil when they cancel.
    func review(_ text: String, modeName: String) async -> String? {
        finish(nil)
        state.text = text
        state.modeName = modeName
        let panel = self.panel ?? makePanel()
        let size = CGSize(width: 440, height: 168)
        // The card goes on the screen with the caret (or the pointer when the caret is unknown).
        let caret = Self.caretRect()
        let anchor = caret.map { CGPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let frame = DictationPreviewLayout.frame(size: size, caret: caret, pointer: NSEvent.mouseLocation,
                                                 visible: screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900))
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.18; panel.animator().alphaValue = 1 }, completionHandler: nil)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
            .announcement: "Dictation ready to check. Return inserts, Escape cancels.",
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
        self.panel = panel
        return await withCheckedContinuation { self.continuation = $0 }
    }

    private func finish(_ result: String?) {
        panel?.orderOut(nil)
        continuation?.resume(returning: result)
        continuation = nil
    }

    private func makePanel() -> PreviewPanel {
        let panel = PreviewPanel(contentRect: CGRect(x: 0, y: 0, width: 440, height: 168),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.onKey = { [weak self] action in
            guard let self else { return false }
            switch action {
            case .insert: self.finish(DictationPreviewResult.finalText(self.state.text)); return true
            case .cancel: self.finish(nil); return true
            case .edit: return false
            }
        }
        panel.contentView = NSHostingView(rootView: DictationPreviewView(state: state,
                                                                          insert: { [weak self] in self?.finish(DictationPreviewResult.finalText(self?.state.text ?? "")) },
                                                                          cancel: { [weak self] in self?.finish(nil) }))
        return panel
    }

    /// The caret of the focused text field, in AppKit coordinates, when the app exposes it.
    static func caretRect() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement // swiftlint:disable:this force_cast
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success, let range else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0 else { return nil } // swiftlint:disable:this force_cast
        // Accessibility measures from the top-left of the primary display and AppKit from its
        // bottom-left, across every display, so the primary display's height converts both.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

final class PreviewPanel: NSPanel {
    var onKey: (DictationPreviewKey) -> Bool = { _ in false }
    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let flags = event.modifierFlags
            let action = DictationPreviewKey.action(keyCode: event.keyCode, shift: flags.contains(.shift), command: flags.contains(.command))
            if action != .edit, onKey(action) { return }
        }
        super.sendEvent(event)
    }
}

struct DictationPreviewView: View {
    let state: DictationPreviewCard.State
    let insert: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(TopBarStyle.rec).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(state.modeName.isEmpty ? "Dictation" : state.modeName).font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
                Spacer()
            }
            TextEditor(text: Binding(get: { state.text }, set: { state.text = $0 }))
                .font(TopBarStyle.label(14))
                .foregroundStyle(Theme.cloudPrimary)
                .snapshotSafeText(state.text, placeholder: "Dictated text", multiline: true)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Dictated text, editable")
            HStack {
                Text("Unanswered for 5 min: copied, not written")
                    .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(PlainTextButtonStyle()).foregroundStyle(Theme.cloudSecondary)
                    .accessibilityHint("Throws this dictation away.")
                Button("Insert", action: insert).buttonStyle(PlainTextButtonStyle()).foregroundStyle(Theme.bolt)
                    .accessibilityHint("Types this text into the app you were in.")
            }
            .font(TopBarStyle.label(12, .semibold))
        }
        .padding(12)
        .background(Theme.storm.opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .preferredColorScheme(.dark)
    }
}
