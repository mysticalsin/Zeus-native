import AppKit
import SwiftUI
import ZeusCore

@Observable
@MainActor
final class PointingTextEntryModel {
    var text = ""
}

private struct PointingTextEntryView: View {
    @Bindable var model: PointingTextEntryModel
    let submit: () -> Void
    let cancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Ask about what is under your pointer", text: $model.text)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .focused($focused)
            .onSubmit(submit)
            .onExitCommand(perform: cancel)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 380)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onAppear { focused = true }
            .accessibilityLabel("Ask Zeus about what is under your pointer")
    }
}

/// Can take keys without activating Zeus, so typing never steals focus from the app being asked about.
private final class PointingTextPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The small box that opens on a double tap of Control. Return sends, Esc or clicking away closes.
/// It is excluded from screen capture, so the box never appears in the screenshot it helps ask about.
@MainActor
final class PointingTextEntry {
    var onSubmit: ((String) -> Void)?
    private var panel: NSPanel?
    private let model = PointingTextEntryModel()
    private var resignObserver: NSObjectProtocol?

    var isVisible: Bool { panel?.isVisible == true }

    /// `point` is an AppKit global point; the box opens just below it, kept on that screen.
    func show(near point: CGPoint) {
        hide()
        model.text = ""
        let view = PointingTextEntryView(model: model, submit: { [weak self] in self?.send() },
                                         cancel: { [weak self] in self?.hide() })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let created = PointingTextPanel(contentRect: NSRect(origin: .zero, size: size),
                                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        created.contentView = host
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        created.level = .screenSaver
        created.hidesOnDeactivate = false
        created.isReleasedWhenClosed = false
        created.sharingType = .none
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        var origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height - 28)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        created.setFrameOrigin(origin)
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: created, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        panel = created
        created.makeKeyAndOrderFront(nil)
    }

    func hide() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func send() {
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        hide()
        guard !text.isEmpty else { return }
        onSubmit?(text)
    }
}
