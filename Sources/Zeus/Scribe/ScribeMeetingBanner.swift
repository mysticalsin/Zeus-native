import AppKit
import Observation
import SwiftUI
import ZeusCore

@MainActor
@Observable
final class ScribeMeetingBannerModel {
    var headline = ""
    var detail = ""
    var appName = ""
    var when = ""
    var symbol = "video"
    /// Empty hides the primary button (the countdown only offers Cancel).
    var primaryTitle = ""
    var secondaryTitle = ""
    /// Only for the Start questions: after a tap, "Starting...", the confirmation, or why it could not start.
    var card: ScribePopupPhase = .shown
    /// Set by `ScribeAutoStartController`.
    @ObservationIgnored var onPrimary: () -> Void = {}
    @ObservationIgnored var onSecondary: () -> Void = {}
    @ObservationIgnored var onPointer: (Bool) -> Void = { _ in }
    /// Set by `ScribeMeetingBanner`: the buttons go through it so a Start tap is tracked to its outcome.
    @ObservationIgnored var primaryTapped: () -> Void = {}
    @ObservationIgnored var secondaryTapped: () -> Void = {}
    @ObservationIgnored var closeTapped: () -> Void = {}
}

/// One meeting notice, for snapshots. Synthetic title and time only.
struct MeetingAlertSnapshot: View {
    var title: String
    var when: String
    var appName: String
    var symbol: String
    var scheme: ColorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(TopBarStyle.label(12, .semibold)).lineLimit(1)
                Text("\(when) · \(appName)").font(TopBarStyle.label(10.5)).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("Start").font(TopBarStyle.label(11, .semibold))
            Text("Not now").font(TopBarStyle.label(11))
        }
        .padding(.horizontal, 10)
        .frame(width: MeetingAlert.width, height: MeetingAlert.height)
        .background(scheme == .dark ? Color.black : Color.white, in: RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, scheme)
    }
}

private struct ScribeMeetingBannerView: View {
    let model: ScribeMeetingBannerModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.headline)
                    .font(TopBarStyle.label(12, .semibold))
                    .foregroundStyle(Theme.cloudPrimary)
                    .lineLimit(1)
                Text("\(model.when) · \(model.appName)")
                    .font(TopBarStyle.label(10.5, .regular))
                    .foregroundStyle(Theme.cloudSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if case .shown = model.card {
                buttons
            } else {
                ScribePopupStatusView(phase: model.card, onAction: model.primaryTapped, onClose: model.closeTapped)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: MeetingAlert.width, height: MeetingAlert.height)
        .alertGlass(radius: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(model.headline), \(model.when), \(model.appName)")
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if !model.primaryTitle.isEmpty {
                Button(model.primaryTitle) { model.primaryTapped() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Starts taking notes for this meeting.")
            }
            Button(model.secondaryTitle) { model.secondaryTapped() }
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
    static let width: CGFloat = MeetingAlert.width
    private static let margin: CGFloat = 16

    private enum Kind {
        case ask, consent, nextMeeting, countdown

        /// The Start questions, whose primary tap starts Scribe and is tracked to its outcome.
        var startsScribe: Bool { self == .ask || self == .consent }
    }

    let model = ScribeMeetingBannerModel()
    private let driver = ScribePopupDriver(name: "meeting banner")
    private var panel: NSPanel?
    private var hostingView: ScribeCardHostingView<ScribeMeetingBannerView>?
    private var kind: Kind = .ask
    private var dismissTask: Task<Void, Never>?
    /// The meeting the card is about.
    private(set) var meeting: ScribeMeeting?

    var isVisible: Bool { panel?.isVisible ?? false }

    private init() {
        model.primaryTapped = { [weak self] in self?.primaryTapped() }
        model.secondaryTapped = { [weak self] in self?.secondaryTapped() }
        model.closeTapped = { [weak self] in self?.closeTapped() }
        driver.onStart = { [weak self] in self?.model.onPrimary() }
        driver.onHide = { [weak self] in self?.panel?.orderOut(nil) }
        driver.onPhase = { [weak self] phase in self?.phaseChanged(phase) }
    }

    func showAsk(_ meeting: ScribeMeeting) {
        guard begin(.ask, meeting) else { return }
        model.headline = ScribeAutoStartText.askHeadline(meeting)
        model.detail = ScribeAutoStartText.askDetail
        model.primaryTitle = "Start"
        model.secondaryTitle = "Not now"
        present(announce: "\(model.headline) Start, or Not now.")
    }

    /// The first time "Start automatically" would fire: one question, and the answer is remembered.
    func showConsent(_ meeting: ScribeMeeting) {
        guard begin(.consent, meeting) else { return }
        model.headline = ScribeAutoStartText.askHeadline(meeting)
        model.detail = ScribeAutoStartText.consentDetail
        model.primaryTitle = "Start and allow"
        model.secondaryTitle = "Not now"
        present(announce: "\(model.headline) Start and allow, or Not now.")
    }

    /// Another meeting is about to start while this one records.
    func showNextMeeting(_ meeting: ScribeMeeting) {
        guard begin(.nextMeeting, meeting) else { return }
        model.headline = ScribeAutoStartText.nextMeetingHeadline(meeting)
        model.detail = ScribeAutoStartText.nextMeetingDetail
        model.primaryTitle = "Switch"
        model.secondaryTitle = "Keep recording"
        present(announce: "\(model.headline) Switch, or Keep recording.")
    }

    func showCountdown(_ meeting: ScribeMeeting, seconds: Int) {
        guard begin(.countdown, meeting) else { return }
        model.headline = ScribeAutoStartText.countdownHeadline(meeting, seconds: seconds)
        model.detail = ScribeAutoStartText.countdownDetail
        model.primaryTitle = ""
        model.secondaryTitle = "Cancel"
        present(announce: "\(model.headline) Cancel to stop it.")
    }

    /// Updates the number without bringing the card forward or announcing again.
    func updateCountdown(_ meeting: ScribeMeeting, seconds: Int) {
        guard isVisible, kind == .countdown else { return }
        model.headline = ScribeAutoStartText.countdownHeadline(meeting, seconds: seconds)
    }

    /// The machine takes the banner down. A Start tap still in flight, or its failure, stays on screen until it
    /// resolves (the machine hides the banner the moment it decides to start).
    func hide() {
        guard !driver.isBusy else { return }
        driver.meetingGone()
        panel?.orderOut(nil)
    }

    /// False while a Start tap is in flight: Scribe is starting, so a new question would only cover the answer.
    private func begin(_ kind: Kind, _ meeting: ScribeMeeting) -> Bool {
        if driver.phase == .starting || driver.phase == .started { return false }
        self.kind = kind
        self.meeting = meeting
        if kind.startsScribe {
            // The machine owns the 20 second timeout (held while the pointer is over the card).
            driver.present(key: meeting.key, lifetime: nil)
        } else {
            driver.dismiss()
        }
        model.card = .shown
        let row = MeetingAlert.model(title: meeting.title, start: meeting.slot?.start, now: Date(), app: meeting.callApp)
        model.headline = meeting.title.isEmpty ? "Meeting" : meeting.title
        model.when = row.when
        model.appName = row.appName
        model.symbol = row.symbol
        return true
    }

    private func primaryTapped() {
        guard kind.startsScribe else {
            ScribePopupDriver.log("click", "meeting banner \(kind)")
            model.onPrimary()
            return
        }
        driver.click()
    }

    private func secondaryTapped() {
        if kind.startsScribe { driver.dismiss() }
        model.onSecondary()
    }

    /// Close on a failure: the person is done with this meeting's question.
    private func closeTapped() {
        driver.dismiss()
        model.onSecondary()
    }

    private func pointer(inside: Bool) {
        if kind.startsScribe { driver.pointer(inside: inside) }
        model.onPointer(inside)
    }

    private func phaseChanged(_ phase: ScribePopupPhase) {
        guard kind.startsScribe else { return }
        model.card = phase.isVisible ? phase : .shown
        guard phase.isVisible, let panel else { return }
        Task { @MainActor [weak self] in self?.layout(panel) }
    }

    private func present(announce: String) {
        let (panel, _) = ensurePanel()
        layout(panel)
        // Front without activating Zeus: whatever the person is typing in keeps the keyboard.
        panel.orderFrontRegardless()
        AccessibilityNotification.Announcement(announce).post()
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(MeetingAlert.dismissAfter))
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }

    private func layout(_ panel: NSPanel) {
        guard let hostingView else { return }
        let size = hostingView.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
    }

    private func ensurePanel() -> (NSPanel, ScribeCardHostingView<ScribeMeetingBannerView>) {
        if let panel, let hostingView { return (panel, hostingView) }
        let host = ScribeCardHostingView(rootView: ScribeMeetingBannerView(model: model))
        host.onPointer = { [weak self] inside in self?.pointer(inside: inside) }
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
        panel.sharingType = .none
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
