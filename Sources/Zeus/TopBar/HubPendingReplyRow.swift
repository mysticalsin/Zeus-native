import SwiftUI
import ZeusCore

/// The selected session and the inline reply row. Approve is the filled control.
/// Deny and Cancel stay quiet. Reduce Motion fades the row in place.
struct AgentReplyPane: View {
    @Bindable var hub: AgentHub
    let session: NotchModel.Session
    @State private var model = HubPendingReplyModel()

    private var canType: Bool { hub.canReply(to: session.id) }
    private var showsPending: Bool {
        hub.replyNeedsApproval && hub.selectedSession == session.id && hub.replyWaitDeadline != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(MeetingState.hideDetails ? "Details hidden" : (session.reason ?? session.task))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.cloudSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            replyField
            if showsPending, let deadline = hub.replyWaitDeadline {
                TimelineView(.periodic(from: deadline.addingTimeInterval(-HubPendingReplyModel.waitSeconds), by: 1)) { context in
                    let now = context.date.timeIntervalSinceReferenceDate
                    if let shown = model.displayed(at: now) {
                        PendingReplyControls(row: shown, now: now) { action, at, focused in
                            perform(action, at: at, focused: focused)
                        }
                        .transition(rowTransition)
                    }
                }
            }
            if !showsPending {
                Text(hub.receipt ?? (canType
                    ? "Approve the line before it is typed."
                    : "This session can't take a typed reply. Open it and reply there."))
                    .font(TopBarStyle.label(10.5))
                    .foregroundStyle(Theme.cloudQuiet)
                    .lineLimit(2)
            }
        }
        .background { if showsPending { escapeCatcher } }
        .onAppear { bind(at: Date().timeIntervalSinceReferenceDate) }
        .onChange(of: hub.replyWaitDeadline) { bind(at: Date().timeIntervalSinceReferenceDate) }
        .modifier(PendingEscape(active: showsPending) { perform(.escape, at: Date().timeIntervalSinceReferenceDate, focused: nil) })
        .animation(rowAnimation, value: showsPending && model.displayed(at: Date().timeIntervalSinceReferenceDate) != nil)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(session.agent.isEmpty ? "Session" : session.agent)
                .font(TopBarStyle.label(13, .semibold))
                .foregroundStyle(Theme.cloudPrimary)
                .lineLimit(1)
            if !MeetingState.hideDetails, !session.project.isEmpty {
                Text(session.project)
                    .font(TopBarStyle.label(11.5))
                    .foregroundStyle(Theme.cloudQuiet)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(session.status.label)
                .font(TopBarStyle.label(11, .semibold))
                .foregroundStyle(Theme.cloudSecondary)
            if AgentTerminals.shared.canJump(to: session.id) {
                Button("Open") { hub.openTerminal(session.id) }
                    .buttonStyle(PressableStyle())
                    .font(TopBarStyle.label(12, .semibold))
                    .foregroundStyle(Theme.cloudSecondary)
                    .accessibilityLabel("Open")
            }
        }
    }

    private var replyField: some View {
        HStack(spacing: 8) {
            TextField(
                canType ? "Reply" : "Open the session to reply",
                text: $hub.replyDraft
            )
            .textFieldStyle(.plain)
            .font(TopBarStyle.label(12.5))
            .foregroundStyle(Theme.cloudPrimary)
            .disabled(!canType || hub.sending)
            .onSubmit { send() }
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(canSend ? Color.black : Theme.cloudQuiet)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(canSend ? Color.white : Color.white.opacity(0.10)))
            }
            .buttonStyle(PressableStyle())
            .disabled(!canSend)
            .accessibilityLabel(hub.sending ? "Sending" : "Send")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 30)
        .background(Color.white.opacity(0.06), in: Capsule())
        .opacity(canType ? 1 : 0.5)
    }

    private var canSend: Bool {
        canType && !hub.sending && !hub.replyNeedsApproval
            && !hub.replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var escapeCatcher: some View {
        Button(action: { perform(.escape, at: Date().timeIntervalSinceReferenceDate, focused: nil) }) {
            EmptyView()
        }
        .keyboardShortcut(.cancelAction)
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        .focusable(false)
    }

    private var rowTransition: AnyTransition {
        let motion = HubPendingReplyModel.motion(reduceMotion: Motion.reduced)
        if motion.usesSpring {
            return .opacity.combined(with: .offset(y: motion.offset))
        }
        return .opacity
    }

    private var rowAnimation: Animation? {
        let motion = HubPendingReplyModel.motion(reduceMotion: Motion.reduced)
        if motion.usesSpring { return TopBarStyle.pageSpring }
        return .easeOut(duration: Motion.crossfadeDuration)
    }

    /// Records the row. It does not approve, deny, or cancel.
    private func bind(at now: TimeInterval) {
        guard let deadline = hub.replyWaitDeadline, showsPending else { return }
        _ = model.present(currentOffer, at: now, deadline: deadline.timeIntervalSinceReferenceDate)
    }

    private var currentOffer: HubPendingReplyOffer {
        let stamp = hub.replyWaitDeadline?.timeIntervalSinceReferenceDate ?? 0
        return HubPendingReplyOffer(
            id: "\(session.id)|\(stamp)",
            destination: replyDestination,
            draft: hub.replyDraft
        )
    }

    private var replyDestination: String {
        let agent = session.agent.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = agent.isEmpty ? "this session" : agent
        if MeetingState.hideDetails { return name }
        let project = session.project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty else { return name }
        return "\(name), \(project)"
    }

    private func send() {
        guard canSend else { return }
        Task { await hub.sendReply(session: session) }
    }

    private func perform(_ action: HubPendingReplyAction, at now: TimeInterval, focused: HubPendingReplyFocus?) {
        let verdict = model.decide(action, id: currentOffer.id, focus: focused, at: now)
        switch verdict {
        case .release:
            Task { await hub.approveReply() }
        case .withhold(_, .deny):
            hub.denyReply()
        case .withhold(_, .cancel):
            hub.cancelReply()
        case .withhold(_, .timeout), .ignore:
            break
        }
    }
}

/// Deny, Cancel, and Approve for one cleaned line. Return follows Approve's focus only.
private struct PendingReplyControls: View {
    let row: HubPendingReplyRow
    let now: TimeInterval
    let onAction: (HubPendingReplyAction, TimeInterval, HubPendingReplyFocus?) -> Void
    @FocusState private var focus: HubPendingReplyFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.destination)
                    .font(TopBarStyle.label(11, .semibold))
                    .foregroundStyle(Theme.cloudPrimary)
                    .lineLimit(1)
                Text(row.line)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.cloudSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                Text(row.caption)
                    .font(TopBarStyle.label(10.5).monospacedDigit())
                    .foregroundStyle(Theme.cloudQuiet)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityHint(row.accessibilityHint)
            .accessibilitySortPriority(HubPendingReplyModel.sortPriority(.summary))

            HStack(spacing: 8) {
                ForEach(row.buttons) { button in
                    Button(button.title) { onAction(button.action, now, focus) }
                        .buttonStyle(PressableStyle())
                        .font(TopBarStyle.label(12, .semibold))
                        .foregroundStyle(button.isPrimary ? Theme.storm : Theme.cloudPrimary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 26)
                        .background(Capsule().fill(button.isPrimary ? Color.white : Color.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(button.isPrimary ? 0 : 0.10), lineWidth: 0.5))
                        .focused($focus, equals: button.focus)
                        .accessibilityLabel(button.label)
                        .accessibilityHint(button.hint)
                        .accessibilitySortPriority(HubPendingReplyModel.sortPriority(button.focus))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .onKeyPress(.return) {
            guard focus == .approve else { return .ignored }
            onAction(.return, Date().timeIntervalSinceReferenceDate, focus)
            return .handled
        }
    }
}

/// Escape reaches the row while it is waiting. It is not installed before that.
private struct PendingEscape: ViewModifier {
    let active: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if active {
            content.onExitCommand(perform: action)
        } else {
            content
        }
    }
}
