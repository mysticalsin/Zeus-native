import AppKit
import Observation
import SwiftUI
import ZeusCore

@MainActor
@Observable
final class ScribeCallPopupModel {
    var headline = ""
    var detail = "Nothing is recorded until you tap Record."
    /// What the card shows after a tap: "Starting...", the confirmation, or why it could not start.
    var card: ScribePopupPhase = .shown
    @ObservationIgnored var onRecord: () -> Void = {}
    @ObservationIgnored var onDismiss: () -> Void = {}
    @ObservationIgnored var onClose: () -> Void = {}
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
            if case .shown = model.card {
                buttons
            } else {
                ScribePopupStatusView(phase: model.card, onAction: model.onRecord, onClose: model.onClose)
            }
        }
        .padding(14)
        .frame(width: ScribeCallPopup.width, alignment: .leading)
        .alertGlass(radius: 16)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scribe suggestion: \(model.headline)")
    }

    private var buttons: some View {
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

    /// Showing this long without an answer counts as "Not now", so it doesn't pop back. Never under the pointer.
    private static let lifetime: TimeInterval = 45
    private static let margin: CGFloat = 16

    private let model = ScribeCallPopupModel()
    private let driver = ScribePopupDriver(name: "heads-up")
    private var panel: NSPanel?
    private var hostingView: ScribeCardHostingView<ScribeCallPopupView>?
    private var current: ScribePromptDecision = .none
    /// The meeting the card last asked about. Kept after the card leaves so a tap already on its way still
    /// starts with the right title.
    private var shown: ScribePromptDecision = .none

    private init() {
        model.onRecord = { [weak self] in self?.driver.click() }
        model.onDismiss = { [weak self] in self?.notNow() }
        model.onClose = { [weak self] in self?.driver.dismiss() }
        driver.onStart = { [weak self] in self?.startScribe() }
        driver.onHide = { [weak self] in self?.panel?.orderOut(nil) }
        driver.onTimedOut = { [weak self] in self?.timedOut() }
        driver.onPhase = { [weak self] phase in self?.phaseChanged(phase) }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func present(_ decision: ScribePromptDecision, now: Date = Date()) {
        guard let headline = ScribeCallPromptText.headline(for: decision, now: now) else {
            hide()
            return
        }
        // A tap in flight, or its failure, stays on screen until it resolves.
        guard !driver.isBusy else { return }
        // The "Meeting started" banner uses the same corner: never cover the card the person may be reaching for.
        guard !ScribeMeetingBanner.shared.isVisible else { return }
        current = decision
        shown = decision
        model.headline = headline
        driver.present(key: Self.key(for: decision), lifetime: Self.lifetime)
        model.card = driver.phase
        let (panel, _) = ensurePanel()
        layout(panel)
        // Front without activating Zeus: whatever the person is typing in keeps the keyboard.
        panel.orderFrontRegardless()
        if #available(macOS 14, *) {
            AccessibilityNotification.Announcement("\(headline). Record with Scribe, or Not now.").post()
        }
    }

    /// The watcher takes the card down (the prompt is over). A card that is starting Scribe or showing why it
    /// could not stays until that resolves.
    func hide() {
        guard !driver.isBusy else { return }
        driver.meetingGone()
        current = .none
        panel?.orderOut(nil)
    }

    /// Refresh the relative start time without bringing the panel forward again or extending its lifetime.
    /// A hidden/dismissed suggestion stays hidden.
    func refresh(now: Date) {
        guard isVisible, !driver.isBusy, let headline = ScribeCallPromptText.headline(for: current, now: now) else { return }
        model.headline = headline
    }

    private func startScribe() {
        let decision = shown
        let controller = ScribeController.shared
        controller.meetingTitleHint = ScribeCallPromptText.meetingTitle(for: decision)
        if case .upcoming(let slot) = decision { controller.meetingAttendeeHint = slot.attendeeNames }
        controller.meetingCallHint = ScribeCallWatcher.shared.recordingIdentity(for: decision)
        controller.start()
    }

    private func notNow() {
        let decision = current
        driver.dismiss()
        ScribeCallWatcher.shared.dismiss(decision)
        current = .none
    }

    private func timedOut() {
        let decision = current
        current = .none
        ScribeCallWatcher.shared.dismiss(decision)
    }

    private func phaseChanged(_ phase: ScribePopupPhase) {
        model.card = phase
        guard phase.isVisible, let panel else { return }
        // The status row changes the card's height: resize once SwiftUI has laid out the new content.
        Task { @MainActor [weak self] in self?.layout(panel) }
    }

    private func layout(_ panel: NSPanel) {
        guard let hostingView else { return }
        let size = hostingView.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
    }

    private static func key(for decision: ScribePromptDecision) -> String {
        switch decision {
        case .none: return "none"
        case .upcoming(let slot): return slot.id
        case .callDetected(let app): return "call:\(ScribeCallDetection.displayName(app))"
        }
    }

    private func ensurePanel() -> (NSPanel, ScribeCardHostingView<ScribeCallPopupView>) {
        if let panel, let hostingView { return (panel, hostingView) }
        let host = ScribeCardHostingView(rootView: ScribeCallPopupView(model: model))
        host.onPointer = { [weak self] inside in self?.driver.pointer(inside: inside) }
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
