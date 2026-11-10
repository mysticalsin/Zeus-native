import AppKit
import SwiftUI
import ZeusCore

/// Lets views that only hold the model reach the controller's few actions.
@MainActor
enum NotchControllerBridge {
    static weak var controller: NotchController?
    static func dismissFailure() { controller?.dismissFailure() }
    static func clickNotificationLine() { controller?.clickNotificationLine() }
    static func closePeek() { if controller?.model.presentation == .peek { controller?.show(.closed) } }
    static func applyScreenSharePolicy(visibleInShare: Bool) { controller?.applyScreenSharePolicy(visibleInShare: visibleInShare) }

    /// A tap on a system notification's Open action: the open panel on the Agents tab, with that
    /// agent's session picked when it is still running.
    static func openAgent(sessionID: String?) {
        guard let controller else { return }
        if let sessionID, controller.model.sessions.contains(where: { $0.id == sessionID }) {
            controller.model.peekSessionID = sessionID
        }
        controller.topBar?.selectedTab = .agents
        controller.show(.panel)
    }
}

/// The peek card for an agent in trouble: red when its turn failed, amber when it went quiet.
/// Says why, and offers the way back to its terminal.
struct AgentTroubleCard: View {
    enum Kind { case failed, stalled }

    let kind: Kind
    let sessionID: String
    let agent: String
    let project: String
    let reason: String
    let dismiss: () -> Void

    static var height: CGFloat { AgentCardLayout<EmptyView>.height }

    private var cardKind: AgentCardKind { kind == .failed ? .failed : .quiet }

    var body: some View {
        AgentCardLayout(agent: agent, project: project, kind: cardKind, summary: reason, dismiss: dismiss) {
            if AgentTerminals.shared.canJump(to: sessionID) {
                CardButton(title: "Open", tint: cardKind.tint, filled: true) {
                    AgentTerminals.shared.jump(to: sessionID)
                    dismiss()
                }
                .accessibilityHint("Brings \(agent)'s terminal forward.")
            }
        }
    }
}

/// Glance-style slim line under the closed notch for a notification from another app.
struct NotchNotificationLine: View {
    static let width: CGFloat = 340
    static let height: CGFloat = 26

    let line: NotchModel.NotificationLine
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 7) {
                if let icon = NotificationsController.shared.icon(line.app) {
                    Image(nsImage: icon).resizable().frame(width: 15, height: 15)
                } else {
                    Image(systemName: "bell.fill").font(.system(size: 10)).foregroundStyle(Theme.cloudSecondary)
                }
                Text(line.title).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                Text(line.detail).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(width: Self.width, height: Self.height)
            .background(Capsule().fill(Color.black))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(line.title). \(line.detail)")
        .accessibilityHint("Opens the app.")
    }
}

/// Watches the mirrored notifications and puts the newest one on the notch's slim line.
@MainActor
final class NotificationPeeker {
    weak var notch: NotchController?
    private var timer: Timer?
    private var lastSeen: Int64?
    private var lastStamp: Date?
    private var polling = false

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: TickRules.notificationPollSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private var enabled: Bool { NotificationsController.shared.enabled && SettingsStore.shared.bool("notify.peek") && !TopBarStyle.isSnapshot }

    private func poll() {
        guard enabled, !polling else {
            if !enabled { lastSeen = nil; lastStamp = nil }
            return
        }
        polling = true
        let known = lastStamp
        let hasBaseline = lastSeen != nil
        Task.detached(priority: .utility) {
            // Nothing was written to the store since the last read: skip the open and the query.
            let stamp = NotificationMirror.changeStamp()
            if hasBaseline, let stamp, stamp == known {
                await MainActor.run { [weak self] in self?.polling = false }
                return
            }
            let result = NotificationMirror.recent(limit: 6)
            await MainActor.run { [weak self] in
                self?.polling = false
                if case .success(let items) = result { self?.lastStamp = stamp; self?.handle(items) }
            }
        }
    }

    func handle(_ items: [MirroredNotification]) {
        guard let notch else { return }
        let store = SettingsStore.shared
        let busy = notch.model.presentation != .closed || notch.model.approval != nil || notch.model.completion != nil || notch.model.failure != nil
        let quiet = MeetingState.active
            || (AgentSettings.shared.quietInFullScreen && FullScreenDetector.frontAppIsFullScreen())
        // The first poll only sets the baseline, so notifications that were already there never flash.
        let context = NotificationPeekRules.Context(
            lastSeenID: lastSeen ?? NotificationPeekRules.newestID(items) ?? 0,
            muted: NotificationPeekRules.mutedSet(store.string("notify.mutedApps")),
            ownBundleID: Bundle.main.bundleIdentifier ?? "app.zeus.mac", notchBusy: busy, quiet: quiet)
        let pick = lastSeen == nil ? nil : NotificationPeekRules.next(from: items, now: Date(), context: context)
        if let newest = NotificationPeekRules.newestID(items), !busy || lastSeen == nil { lastSeen = max(newest, lastSeen ?? newest) }
        guard let pick else { return }
        let name = NotificationsController.shared.appName(pick.app)
        let text = NotificationPeekRules.line(for: pick, appName: name, showDetails: store.bool("notify.peekDetails") && !MeetingState.hideDetails)
        notch.showNotificationLine(.init(id: pick.id, app: pick.app, title: text.title, detail: text.detail))
    }
}
