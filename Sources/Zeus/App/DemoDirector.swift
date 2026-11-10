import AppKit

/// Plays the ZEUS experience end to end with scripted data, so the look can be judged before
/// voice and agent hooks are wired: listen → think → fly + strike → agent peek → approval
/// (click Approve or Deny) → done → panel.
@MainActor
final class DemoDirector {
    private let buddy: BuddyController
    private let notch: NotchController
    private let statusItemFrame: () -> CGRect?
    private var task: Task<Void, Never>?

    init(buddy: BuddyController, notch: NotchController, statusItemFrame: @escaping () -> CGRect?) {
        self.buddy = buddy
        self.notch = notch
        self.statusItemFrame = statusItemFrame
    }

    func play() {
        task?.cancel()
        task = Task { await run() }
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private func run() async {
        notch.model.sessions = []
        notch.model.approval = nil
        notch.show(.closed)
        buddy.idle()
        guard await pause(1.2) else { return }

        // 1. Voice turn: hold the key, talk, release.
        buddy.listen()
        guard await pause(2.6) else { return }
        buddy.think()
        guard await pause(1.2) else { return }

        // 2. The answer points at something real on screen: ZEUS's own menu-bar icon.
        let mainFrame = (NSScreen.main ?? NSScreen.screens[0]).frame
        let iconTarget = statusItemFrame().map { CGPoint(x: $0.midX, y: $0.minY - 6) }
            ?? CGPoint(x: mainFrame.midX, y: mainFrame.midY)
        buddy.point(to: iconTarget, label: "that's me up here, click the bolt anytime")
        guard await pause(7.5) else { return }

        // 3. A coding agent starts work; the notch peeks.
        notch.startSession(id: "cc", agent: "Claude Code", project: "zeus", task: "npm run build")
        guard await pause(3.2) else { return }

        // 4. It asks for permission. The spark flies to the Approve button.
        async let verdict = notch.requestApproval(
            agent: "Claude Code", project: "zeus", tool: "Bash",
            command: "rm -rf dist && npm run build", risk: .high, timeout: .seconds(15)
        )
        notch.update(sessionID: "cc", status: .needsYou)
        guard await pause(0.6) else { return }
        if let approve = notch.approveButtonPoint {
            buddy.point(to: approve, label: "approve or deny, or just say ok")
        }
        let decision = await verdict
        guard !Task.isCancelled else { return }

        // 5. Outcome.
        if decision == .allow {
            notch.update(sessionID: "cc", status: .working, task: "npm run build")
            guard await pause(2.4) else { return }
            notch.update(sessionID: "cc", status: .done, task: "build finished in 41 s")
        } else {
            notch.update(sessionID: "cc", status: .done, task: "denied: rm -rf dist")
        }
        guard await pause(2.0) else { return }

        // 6. More agents, then the full panel.
        notch.startSession(id: "codex", agent: "Codex", project: "website", task: "write tests for checkout")
        notch.startSession(id: "cursor", agent: "Cursor", project: "api", task: "refactor auth middleware")
        notch.update(sessionID: "cursor", status: .done)
        notch.show(.panel)
        guard await pause(6.0) else { return }
        notch.model.peekSessionID = "codex"
        notch.show(.peek)
        guard await pause(1.5) else { return }
        notch.show(.closed)
    }
}
