import AppKit
import Observation
import SwiftUI
import ZeusCore

/// Not wired to any runner yet: nothing creates sessions, and "steer the agent" phrases are not
/// handled by voice (they fall through to a normal turn), so Zeus never claims a steer it can't deliver.
@MainActor
@Observable
final class BackgroundAgentTracker {
    static let shared = BackgroundAgentTracker()

    private(set) var sessions: [BackgroundAgentSession] = []

    /// The newest session that has not finished; nil while nothing runs in the background.
    var activeSession: BackgroundAgentSession? { sessions.first { $0.finished == nil } }

    func moveToBackground(title: String, started: Date = Date()) -> BackgroundAgentSession {
        var session = BackgroundAgentSession(title: title, started: started, engine: .ollama)
        session.appendStep("Started")
        sessions.insert(session, at: 0)
        return session
    }

    func steer(sessionID: UUID, message: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].steer(message)
    }

    func appendStep(sessionID: UUID, title: String, detail: String = "") {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].appendStep(title, detail: detail)
    }

    func finish(sessionID: UUID, holdForTyping: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        if holdForTyping, BackgroundAgentCoordinator.holdCompletionWhileTyping(isTyping: true, finished: Date()) {
            // Held so the card does not land mid-sentence, but never forever: finish a few seconds later.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                self?.finish(sessionID: sessionID, holdForTyping: false)
            }
            return
        }
        sessions[index].finished = Date()
    }
}

struct BackgroundAgentChipView: View {
    let session: BackgroundAgentSession
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title).font(.system(size: AgentsDynamicType.points(11, dynamicTypeSize: dynamicTypeSize), weight: .semibold, design: .rounded))
            ForEach(Array(session.steps.suffix(3).enumerated()), id: \.offset) { _, step in
                Text(step.title).font(.system(size: AgentsDynamicType.points(10, dynamicTypeSize: dynamicTypeSize), weight: .medium, design: .rounded)).lineLimit(1)
            }
        }
        .padding(8)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .windowBackgroundColor))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial)
            }
        }
    }
}
