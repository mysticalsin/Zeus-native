import AppKit
import Foundation
import SwiftUI
import ZeusCore

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

/// Runs one card's `ScribePopupLifecycle`: feeds it taps, the pointer, Scribe's phase and the time, performs its
/// effects, and logs every step so a lost tap can be found afterwards ("[ZEUS] scribe popup: ...").
@MainActor
final class ScribePopupDriver {
    private(set) var lifecycle = ScribePopupLifecycle()
    private let name: String
    private var timer: Timer?

    /// Start Scribe for the meeting on the card.
    var onStart: () -> Void = {}
    /// Take the panel down.
    var onHide: () -> Void = {}
    /// The card ran out of time without an answer.
    var onTimedOut: () -> Void = {}
    /// The card's phase changed: redraw and resize.
    var onPhase: (ScribePopupPhase) -> Void = { _ in }

    init(name: String) {
        self.name = name
    }

    var phase: ScribePopupPhase { lifecycle.phase }
    var isBusy: Bool { lifecycle.isBusy }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func present(key: String, lifetime: TimeInterval?) {
        send(.present(key: key, lifetime: lifetime, now: now))
        Self.log("shown", "\(name) \(Self.describe(lifecycle.phase))")
    }

    /// The primary button: Record / Start, or the failure's Allow / Try again.
    func click() {
        let scribe = ScribeController.shared.phase
        let blocked = ScribeLiveCaptureProvider.microphoneIssue != nil
        Self.log("click", "\(name) card=\(Self.describe(lifecycle.phase)) scribe=\(Self.describe(scribe)) mic=\(blocked ? "blocked" : "ok")")
        send(.click(now: now, scribe: scribe, microphoneBlocked: blocked))
    }

    func pointer(inside: Bool) {
        send(.pointer(inside: inside, now: now))
    }

    func dismiss() {
        send(.dismiss(now: now))
    }

    /// The card's owner took it down (the meeting is over, or no longer offered).
    func meetingGone() {
        send(.meetingGone(now: now))
    }

    private func send(_ event: ScribePopupLifecycle.Event) {
        let before = lifecycle.phase
        let effects = lifecycle.handle(event)
        for effect in effects {
            switch effect {
            case .requestStart:
                Self.log("start requested", name)
                onStart()
                // `ScribeController.start()` reaches `.starting` synchronously, or refuses: read it right away.
                _ = lifecycle.handle(.scribe(ScribeController.shared.phase, now: now))
            case .openMicrophoneSettings:
                Self.log("open settings", "\(name) Privacy_Microphone")
                ScribeSettingsLink.open(pane: "Privacy_Microphone")
            case .hide:
                onHide()
            case .timedOut:
                Self.log("timed out", name)
                onTimedOut()
            }
        }
        report(from: before)
        syncTimer()
    }

    /// Logs the outcome once, when the phase changes, and redraws.
    private func report(from before: ScribePopupPhase) {
        let phase = lifecycle.phase
        guard phase != before else { return }
        switch phase {
        case .started:
            Self.log("start ok", name)
        case .failed(let failure):
            Self.log("start failed", "\(name): \(failure.logReason)")
        default:
            break
        }
        onPhase(phase)
    }

    private func tick() {
        let before = lifecycle.phase
        _ = lifecycle.handle(.scribe(ScribeController.shared.phase, now: now))
        report(from: before)
        send(.tick(now: now))
    }

    private func syncTimer() {
        if lifecycle.needsTick {
            guard timer == nil else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    static func log(_ stage: String, _ detail: String) {
        NSLog("[ZEUS] scribe popup: %@ %@", stage, detail)
        FlightRecorder.shared.record("scribe", "popup \(stage)", detail)
    }

    static func describe(_ phase: ScribePhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .starting: return "starting"
        case .recording: return "recording"
        case .ending: return "ending"
        case .processing: return "processing"
        case .complete: return "complete"
        case .failed(_, let reason): return "failed(\(reason))"
        }
    }

    static func describe(_ phase: ScribePopupPhase) -> String {
        switch phase {
        case .hidden: return "hidden"
        case .shown: return "shown"
        case .starting: return "starting"
        case .started: return "started"
        case .failed(let failure): return "failed(\(failure.logReason))"
        case .expired: return "expired"
        case .dismissed: return "dismissed"
        }
    }
}

/// What a card shows in place of its buttons once tapped: "Starting...", the recording confirmation, or the
/// failure with its fix.
struct ScribePopupStatusView: View {
    let phase: ScribePopupPhase
    let onAction: () -> Void
    let onClose: () -> Void

    var body: some View {
        switch phase {
        case .starting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Starting\u{2026}")
                    .font(TopBarStyle.label(12, .semibold))
                    .foregroundStyle(Theme.cloudPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Scribe is starting")
        case .started:
            Label("Scribe is recording", systemImage: "record.circle")
                .font(TopBarStyle.label(12, .semibold))
                .foregroundStyle(Theme.cloudPrimary)
        case .failed(let failure):
            VStack(alignment: .leading, spacing: 8) {
                Text(failure.message)
                    .font(TopBarStyle.label(11, .regular))
                    .foregroundStyle(Theme.cloudPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(failure.actionTitle, action: onAction)
                        .buttonStyle(.borderedProminent)
                    Button("Close", action: onClose)
                        .buttonStyle(.bordered)
                }
            }
        case .hidden, .shown, .expired, .dismissed:
            EmptyView()
        }
    }
}
