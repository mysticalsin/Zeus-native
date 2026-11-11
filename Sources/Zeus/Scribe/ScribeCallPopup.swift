import AppKit
import Observation
import SwiftUI
import ZeusCore

@MainActor
@Observable
final class ScribeCallPopupModel {
    var headline = ""
    var detail = "Nothing is recorded until you tap Record."
    @ObservationIgnored var onRecord: () -> Void = {}
    @ObservationIgnored var onDismiss: () -> Void = {}
}

private struct ScribeCallPopupView: View {
    let model: ScribeCallPopupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.headline)
                .font(TopBarStyle.label(13, .semibold))
                .foregroundStyle(Theme.cloudPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.detail)
                .font(TopBarStyle.label(11, .regular))
                .foregroundStyle(Theme.cloudSecondary)
            HStack(spacing: 8) {
                Button {
                    model.onRecord()
                } label: {
                    Label("Record with Scribe", systemImage: "waveform")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Record with Scribe")
                .accessibilityHint("Starts listening to this meeting and taking notes.")
                Button("Not now") {
                    model.onDismiss()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Not now")
                .accessibilityHint("Closes this suggestion without recording.")
            }
        }
        .padding(14)
        .frame(width: ScribeCallPopup.width, alignment: .leading)
        .alertGlass(radius: 16)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scribe suggestion: \(model.headline)")
    }
}

/// Never takes focus: it is non-activating and only becomes key if a control inside needs the keyboard
/// (a click on a button doesn't). It can still be reached with VoiceOver and Full Keyboard Access.
private final class ScribePopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The top-right "Meeting detected" or "Starts in N min" card with a one-tap "Record with Scribe".
@MainActor
final class ScribeCallPopup {
    static let shared = ScribeCallPopup()
    static let width: CGFloat = 340

    private static let autoHideAfter: Duration = .seconds(45)
    private static let margin: CGFloat = 16

    private let model = ScribeCallPopupModel()
    private var panel: NSPanel?
    private var hostingView: NSHostingView<ScribeCallPopupView>?
    private var current: ScribePromptDecision = .none
    private var autoHide: Task<Void, Never>?

    private init() {
        model.onRecord = { [weak self] in self?.record() }
        model.onDismiss = { [weak self] in self?.notNow() }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func present(_ decision: ScribePromptDecision, now: Date = Date()) {
        guard let headline = ScribeCallPromptText.headline(for: decision, now: now) else {
            hide()
            return
        }
        current = decision
        model.headline = headline
        let (panel, host) = ensurePanel()
        let size = host.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
        // Front without activating Zeus: whatever the person is typing in keeps the keyboard.
        panel.orderFrontRegardless()
        if #available(macOS 14, *) {
            AccessibilityNotification.Announcement("\(headline). Record with Scribe, or Not now.").post()
        }
        scheduleAutoHide()
    }

    func hide() {
        autoHide?.cancel()
        autoHide = nil
        current = .none
        panel?.orderOut(nil)
    }

    /// Refresh the relative start time without bringing the panel forward again or extending its lifetime.
    /// A hidden/dismissed suggestion stays hidden.
    func refresh(now: Date) {
        guard isVisible, let headline = ScribeCallPromptText.headline(for: current, now: now) else { return }
        model.headline = headline
    }

    private func record() {
        let decision = current
        hide()
        guard decision != .none else { return }
        let controller = ScribeController.shared
        guard !controller.phase.isActive else { return }
        controller.meetingTitleHint = ScribeCallPromptText.meetingTitle(for: decision)
        if case .upcoming(let slot) = decision { controller.meetingAttendeeHint = slot.attendeeNames }
        controller.meetingCallHint = ScribeCallWatcher.shared.recordingIdentity(for: decision)
        controller.start()
    }

    private func notNow() {
        ScribeCallWatcher.shared.dismiss(current)
        hide()
    }

    /// Showing for 45 s and then leaving counts as "Not now" for this prompt, so it doesn't pop back.
    private func scheduleAutoHide() {
        autoHide?.cancel()
        autoHide = Task { [weak self] in
            try? await Task.sleep(for: Self.autoHideAfter)
            guard !Task.isCancelled, let self else { return }
            self.notNow()
        }
    }

    private func ensurePanel() -> (NSPanel, NSHostingView<ScribeCallPopupView>) {
        if let panel, let hostingView { return (panel, hostingView) }
        let host = NSHostingView(rootView: ScribeCallPopupView(model: model))
        let panel = ScribePopupPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 110),
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
        panel.setAccessibilityLabel("Scribe suggestion")
        self.panel = panel
        self.hostingView = host
        return (panel, host)
    }

    private func origin(for size: NSSize) -> NSPoint {
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(
            x: frame.maxX - size.width - Self.margin,
            y: frame.maxY - size.height - Self.margin
        )
    }
}
