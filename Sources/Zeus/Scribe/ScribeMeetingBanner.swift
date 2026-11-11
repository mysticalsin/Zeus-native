import AppKit
import Observation
import SwiftUI
import ZeusCore

@MainActor
@Observable
final class ScribeMeetingBannerModel {
    var headline = ""
    var detail = ""
    /// Empty hides the primary button (the countdown only offers Cancel).
    var primaryTitle = ""
    var secondaryTitle = ""
    @ObservationIgnored var onPrimary: () -> Void = {}
    @ObservationIgnored var onSecondary: () -> Void = {}
}

private struct ScribeMeetingBannerView: View {
    let model: ScribeMeetingBannerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.headline)
                .font(TopBarStyle.label(13, .semibold))
                .foregroundStyle(Theme.cloudPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.detail)
                .font(TopBarStyle.label(11, .regular))
                .foregroundStyle(Theme.cloudSecondary)
            buttons
        }
        .padding(14)
        .frame(width: ScribeMeetingBanner.width, alignment: .leading)
        .alertGlass(radius: 16)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scribe: \(model.headline)")
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if !model.primaryTitle.isEmpty {
                Button(model.primaryTitle) { model.onPrimary() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Starts taking notes for this meeting.")
            }
            Button(model.secondaryTitle) { model.onSecondary() }
                .buttonStyle(.bordered)
                .accessibilityHint("Closes this without recording.")
        }
    }
}

/// Same rule as the other Scribe cards: it never takes focus from what the person is typing in.
private final class ScribeBannerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The top-right "Meeting started: <title>. Take notes?" card. "Ask me" shows Start and Not now; "Start
/// automatically" shows the countdown with Cancel. It only draws what `ScribeAutoStartController` tells it to;
/// the 20 second and 5 second deadlines live in the core machine, not here.
@MainActor
final class ScribeMeetingBanner {
    static let shared = ScribeMeetingBanner()
    static let width: CGFloat = 340
    private static let margin: CGFloat = 16

    let model = ScribeMeetingBannerModel()
    private var panel: NSPanel?
    private var hostingView: NSHostingView<ScribeMeetingBannerView>?

    var isVisible: Bool { panel?.isVisible ?? false }

    func showAsk(_ meeting: ScribeMeeting) {
        model.headline = ScribeAutoStartText.askHeadline(meeting)
        model.detail = ScribeAutoStartText.askDetail
        model.primaryTitle = "Start"
        model.secondaryTitle = "Not now"
        present(announce: "\(model.headline) Start, or Not now.")
    }

    /// The first time "Start automatically" would fire: one question, and the answer is remembered.
    func showConsent(_ meeting: ScribeMeeting) {
        model.headline = ScribeAutoStartText.askHeadline(meeting)
        model.detail = ScribeAutoStartText.consentDetail
        model.primaryTitle = "Start and allow"
        model.secondaryTitle = "Not now"
        present(announce: "\(model.headline) Start and allow, or Not now.")
    }

    /// Another meeting is about to start while this one records.
    func showNextMeeting(_ meeting: ScribeMeeting) {
        model.headline = ScribeAutoStartText.nextMeetingHeadline(meeting)
        model.detail = ScribeAutoStartText.nextMeetingDetail
        model.primaryTitle = "Switch"
        model.secondaryTitle = "Keep recording"
        present(announce: "\(model.headline) Switch, or Keep recording.")
    }

    func showCountdown(_ meeting: ScribeMeeting, seconds: Int) {
        model.headline = ScribeAutoStartText.countdownHeadline(meeting, seconds: seconds)
        model.detail = ScribeAutoStartText.countdownDetail
        model.primaryTitle = ""
        model.secondaryTitle = "Cancel"
        present(announce: "\(model.headline) Cancel to stop it.")
    }

    /// Updates the number without bringing the card forward or announcing again.
    func updateCountdown(_ meeting: ScribeMeeting, seconds: Int) {
        guard isVisible else { return }
        model.headline = ScribeAutoStartText.countdownHeadline(meeting, seconds: seconds)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func present(announce: String) {
        let (panel, host) = ensurePanel()
        let size = host.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
        // Front without activating Zeus: whatever the person is typing in keeps the keyboard.
        panel.orderFrontRegardless()
        AccessibilityNotification.Announcement(announce).post()
    }

    private func ensurePanel() -> (NSPanel, NSHostingView<ScribeMeetingBannerView>) {
        if let panel, let hostingView { return (panel, hostingView) }
        let host = NSHostingView(rootView: ScribeMeetingBannerView(model: model))
        let panel = ScribeBannerPanel(
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
        panel.setAccessibilityLabel("Scribe meeting")
        self.panel = panel
        self.hostingView = host
        return (panel, host)
    }

    private func origin(for size: NSSize) -> NSPoint {
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: frame.maxX - size.width - Self.margin, y: frame.maxY - size.height - Self.margin)
    }
}
