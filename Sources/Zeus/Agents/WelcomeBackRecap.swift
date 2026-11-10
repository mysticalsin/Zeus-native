import AppKit
import SwiftUI
import ZeusCore

/// "Welcome back": after 10 minutes or more with no keyboard or mouse input, the first sign of Tony shows a recap card
/// of what agents finished, failed or are waiting on in the meantime, and Zeus says one line about it (voice answers on).
@MainActor
final class WelcomeBackCoordinator {
    static let shared = WelcomeBackCoordinator()

    private var tracker = AwayTracker()
    private var log = RecapLog()
    private var collapseTask: Task<Void, Never>?
    var speak: (String) -> Void = { _ in }

    static var enabled: Bool { SettingsStore.shared.bool("general.welcomeBack") }

    /// System idle time: seconds since the last key, click or mouse move.
    static func systemIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func poll(notch: NotchController, now: Date = Date(), idle: TimeInterval = WelcomeBackCoordinator.systemIdleSeconds()) {
        let model = notch.model
        let sessions = model.sessions.map { RecapSession(id: $0.id, agent: $0.agent, project: $0.project, status: $0.status, reason: $0.reason) }
        let approval = model.approval.map { (id: $0.id, session: $0.sessionID, agent: $0.agent, project: $0.project, tool: $0.tool) }
        log.observe(sessions: sessions, approval: approval, now: now)
        guard let back = tracker.update(idle: idle, now: now), Self.enabled else { return }
        let waiting = RecapLog.waitingNow(sessions: sessions, approvalID: approval.map { $0.session ?? $0.id })
        guard let recap = WelcomeRecap.make(events: log.events, awayStart: back.awayStart, awaySeconds: back.awaySeconds, stillWaiting: waiting) else { return }
        present(recap, notch: notch)
    }

    func present(_ recap: WelcomeRecap, notch: NotchController) {
        let summary = WelcomeRecapCardView.summaryText(recap, hidden: MeetingState.hideDetails)
        FlightRecorder.shared.record("agent", "welcomeBack", "\(recap.awayText): \(summary)")
        notch.model.recap = recap
        if notch.model.presentation == .closed { notch.show(.peek) }
        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, notch.model.recap != nil, notch.model.presentation == .peek else { return }
            notch.show(.closed)
        }
        if SettingsStore.shared.bool("voice.answers"), !MeetingState.active {
            speak(ZeusVoiceLines.line(for: .welcomeBack, context: ["summary": summary]))
        }
    }
}

/// The recap card in the peek: a header, then one row per agent with an Open button.
struct WelcomeRecapCardView: View {
    let recap: WelcomeRecap
    let dismiss: () -> Void

    static let maxRows = 4
    static func height(for recap: WelcomeRecap) -> CGFloat { 34 + CGFloat(min(recap.all.count, maxRows)) * 32 + (recap.all.count > maxRows ? 16 : 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "hand.wave.fill").font(.system(size: 12)).foregroundStyle(Theme.glow).accessibilityHidden(true)
                Text("Welcome back").font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(Theme.cloudPrimary)
                Text(recap.awayText).font(.system(size: 10.5, design: .rounded)).foregroundStyle(Theme.cloudQuiet)
                Spacer(minLength: 4)
                Text(shownSummary).font(.system(size: 10.5, design: .rounded)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
                AgentCardDismissButton(action: dismiss)
            }
            ForEach(Array(recap.all.prefix(Self.maxRows).enumerated()), id: \.offset) { _, event in row(event) }
            if recap.all.count > Self.maxRows {
                Text("+ \(recap.all.count - Self.maxRows) more").font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.cloudQuiet)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome back. \(shownSummary)")
    }

    /// The recap's own summary names projects, so a count stands in while details are hidden.
    private var shownSummary: String { Self.summaryText(recap, hidden: MeetingState.hideDetails) }

    static func summaryText(_ recap: WelcomeRecap, hidden: Bool) -> String {
        hidden ? "\(recap.all.count) update\(recap.all.count == 1 ? "" : "s")" : recap.summary
    }

    /// Same grammar as the peek cards: avatar, project with the agent in secondary, one line of
    /// detail, the status chip and at most one action.
    private func row(_ event: RecapEvent) -> some View {
        let kind = Self.cardKind(event.kind)
        let hidden = MeetingState.hideDetails
        let detail = hidden ? "" : (event.detail ?? "")
        return HStack(spacing: 8) {
            BotAvatarView.forAgent(event.agent, state: kind.avatarState, size: 24)
            if !hidden {
                Text(event.project).font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
            }
            Text([event.agent, detail].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                .font(.system(size: 10.5, design: .rounded)).foregroundStyle(Theme.cloudSecondary).lineLimit(1).truncationMode(.tail)
                .help(detail.isEmpty ? event.agent : detail)
            Spacer(minLength: 4)
            AgentStatusChip(kind: kind)
            if AgentTerminals.shared.canJump(to: event.id) || TopBarStyle.isSnapshot {
                CardButton(title: "Open", tint: kind.tint, filled: event.kind != .finished) {
                    AgentTerminals.shared.jump(to: event.id)
                    dismiss()
                }
                .accessibilityHint("Brings \(event.agent)'s terminal forward.")
            }
        }
        .frame(height: 26)
        .accessibilityElement(children: .contain)
        .accessibilityLabel([event.agent, kind.label, hidden ? nil : event.project, detail.isEmpty ? nil : detail]
            .compactMap { $0 }.joined(separator: ". "))
    }

    /// Glyph, tint and word for a recap kind (kept for callers that draw their own rows).
    static func style(_ kind: RecapEvent.Kind) -> (String, Color, String) {
        let card = cardKind(kind)
        let word: String = switch kind { case .finished: "finished"; case .failed: "failed"; case .waiting: "waiting for you" }
        return (card.symbol, card.tint, word)
    }

    static func cardKind(_ kind: RecapEvent.Kind) -> AgentCardKind {
        switch kind {
        case .finished: .done
        case .failed: .failed
        case .waiting: .needsYou
        }
    }
}
