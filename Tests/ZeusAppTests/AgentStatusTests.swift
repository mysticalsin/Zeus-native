import Foundation
import Testing
import ZeusCore
@testable import Zeus

@Suite("Notch agent status")
@MainActor
struct AgentStatusTests {
    let start = Date(timeIntervalSince1970: 50_000)

    func model(_ sessions: [NotchModel.Session]) -> NotchModel {
        let model = NotchModel()
        model.sessions = sessions
        return model
    }

    func session(_ id: String, _ status: NotchModel.Status, lastEvent: Date? = nil) -> NotchModel.Session {
        NotchModel.Session(id: id, agent: "Claude Code", project: "zeus", task: "working", status: status,
                           startedAt: start, lastEventAt: lastEvent ?? start)
    }

    @Test func workingSessionStallsAfterTheLimitWithAFakeClock() {
        let model = model([session("a", .working), session("b", .done), session("c", .needsYou)])
        #expect(model.checkStalls(now: start.addingTimeInterval(299), threshold: 300).isEmpty)
        let stalled = model.checkStalls(now: start.addingTimeInterval(301), threshold: 300)
        #expect(stalled.map(\.id) == ["a"])
        #expect(model.sessions[0].status == .stalled)
        #expect(model.sessions[0].reason == "No activity for 5 min")
        #expect(model.sessions[1].status == .done && model.sessions[2].status == .needsYou)
        // A second check does not report it again.
        #expect(model.checkStalls(now: start.addingTimeInterval(400), threshold: 300).isEmpty)
    }

    @Test func halosPickTheMostUrgentState() {
        #expect(model([session("a", .working)]).status == .working)
        #expect(model([session("a", .working), session("b", .stalled)]).status == .stalled)
        #expect(model([session("a", .stalled), session("b", .failed)]).status == .failed)
        let withFailureCard = model([session("a", .working)])
        withFailureCard.failure = .init(sessionID: "a", agent: "Claude Code", project: "zeus", reason: "Rate limit reached")
        #expect(withFailureCard.status == .failed)
        // A permission request outranks everything.
        withFailureCard.approval = .init(id: "x", agent: "Claude Code", project: "zeus", tool: "Bash", command: "ls", risk: .low, resolve: { _ in })
        #expect(withFailureCard.status == .needsYou)
    }

    @Test func failedAndStalledHaveTheirOwnColours() {
        #expect(NotchModel.Status.failed.color == Theme.danger)
        #expect(NotchModel.Status.stalled.color == Theme.amber)
        #expect(NotchModel.Status.failed.label == "Failed" && NotchModel.Status.stalled.label == "Stalled")
    }

    @Test func aNewEventResumesAStalledSession() {
        let controller = NotchController()
        controller.now = { Date(timeIntervalSince1970: 50_100) }
        controller.model.sessions = [session("a", .stalled)]
        controller.touch(sessionID: "a")
        #expect(controller.model.sessions[0].status == .working)
        controller.upsertSession(id: "a", agent: "Claude Code", project: "zeus", task: "next", status: .failed)
        controller.upsertSession(id: "a", agent: "Claude Code", project: "zeus", task: "again", status: .working)
        #expect(controller.model.sessions[0].status == .working && controller.model.sessions[0].reason == nil)
        #expect(controller.model.sessions[0].lastEventAt == Date(timeIntervalSince1970: 50_100))
    }

    @Test func trustedChatStoreAppliesTheRules() {
        let store = TrustedChatStore()
        store.trust(session: "s", agent: "Codex", project: "site")
        #expect(store.summary == "1 chat")
        let input = JSONValue.object(["command": .string("ls")])
        #expect(store.autoApproves(session: "s", tool: "Bash", input: input, risk: .low))
        store.revoke(session: "s")
        #expect(!store.autoApproves(session: "s", tool: "Bash", input: input, risk: .low) && store.summary == "None")
    }

    @Test func stopAllHaltsStartedAndHookedRunsAndLeavesTheApproval() {
        let controller = NotchController()
        controller.startSession(id: "started", agent: "Browser agent", project: "web", task: "click")
        controller.upsertSession(id: "hooked", agent: "Claude Code", project: "zeus", task: "edit", status: .working)
        controller.upsertSession(id: "idle", agent: "Codex", project: "zeus", task: "ready", status: .idle)
        var stopped: [String] = []
        controller.model.stopHandlers["started"] = { stopped.append("handler") }
        var interrupted: [String] = []
        controller.interruptHookedRun = { interrupted.append($0) }
        controller.model.approval = .init(id: "card", agent: "Claude Code", project: "zeus", tool: "Bash",
                                           command: "ls", risk: .low, resolve: { _ in })
        let ids = controller.stopAllSupervised()
        #expect(ids == ["started", "hooked"])
        #expect(stopped == ["handler"])
        #expect(interrupted == ["hooked"])
        #expect(controller.model.approval?.id == "card")
        #expect(controller.model.approval?.command == "ls")
        #expect(controller.model.sessions.first { $0.id == "started" }?.origin == .started)
        #expect(controller.model.sessions.first { $0.id == "started" }?.task == "Stopped")
        #expect(controller.model.sessions.first { $0.id == "hooked" }?.origin == .hooked)
        #expect(controller.model.sessions.first { $0.id == "hooked" }?.status == .idle)
        #expect(controller.model.sessions.first { $0.id == "idle" }?.task == "ready")
        controller.upsertSession(id: "hooked", agent: "Claude Code", project: "zeus", task: "again", status: .working)
        #expect(controller.model.sessions.first { $0.id == "hooked" }?.task == "Stopped")
        #expect(controller.isHalted("hooked"))
        #expect(controller.model.approval != nil)
    }

    @Test func agentAlertTextHidesTheProjectWhenDetailsAreHidden() {
        let alert = AgentAlert.failed(agent: "Codex", project: "secret-app", reason: "Rate limit reached")
        // The project name rides in the title (and thread) when details are shown, never in the body.
        let shown = alert.payload(showDetails: true), hidden = alert.payload(showDetails: false)
        #expect(shown.title.contains("secret-app"))
        for text in [hidden.title, hidden.body, hidden.threadIdentifier ?? ""] {
            #expect(!text.contains("secret-app"), "hidden details keep the project name out of the banner: \(text)")
        }
        #expect(AgentAlert.stalled(agent: "Codex", project: "p", minutes: 5).payload(showDetails: true).body.contains("5 min"))
    }
}
