import Foundation
import Observation
import ZeusCore

@MainActor
@Observable
final class NotchModel {
    /// idle, working, needsYou, done, plus failed (red) and stalled (amber).
    typealias Status = AgentRunState

    enum Presentation: Equatable {
        case closed, peek, panel
    }

    struct Session: Identifiable, Equatable {
        let id: String
        var agent: String
        var project: String
        var task: String
        var status: Status
        var startedAt: Date
        /// The last hook event for this session; stall detection measures from here.
        var lastEventAt = Date()
        /// Why it failed or stalled, for the card.
        var reason: String?
    }

    /// The red card in the peek after an agent's turn ends in an error.
    struct Failure: Equatable {
        var sessionID: String
        var agent: String
        var project: String
        var reason: String
    }

    /// The slim line under the closed notch for a notification from another app.
    struct NotificationLine: Equatable, Identifiable {
        var id: Int64
        var app: String
        var title: String
        var detail: String
    }

    struct Approval: Identifiable {
        let id: String
        var agent: String
        var project: String
        var tool: String
        var command: String
        var risk: HookEvent.Risk
        /// When the card gives up, and what happens then; shown as a countdown on the card.
        var deadline: Date?
        var timeoutNote = ""
        /// Plan, question or diff shown inside the card (Claude Code).
        var detail: ApprovalDetail?
        /// The agent session, for "Allow this whole chat". Nil hides that button.
        var sessionID: String?
        /// Trusts the session, then approves (set only when the request is safe enough to offer it).
        var trustChat: (@MainActor () -> Void)?
        var resolve: @MainActor (HookDecision.Verdict) -> Void

        /// True for a Send/Trash/Buy/Change preview, shown as a multi-line block above the buttons.
        static func isChangePreview(_ command: String) -> Bool {
            guard let first = command.split(separator: "\n", maxSplits: 1).first else { return false }
            return ["Send", "Trash", "Buy", "Change"].contains(String(first))
        }

        /// Height a change preview adds above the buttons: up to 8 wrapped monospaced lines
        /// (about 55 characters each at 12 pt), 7 pt padding each side and 8 pt spacing. 0 otherwise.
        @MainActor var previewHeight: CGFloat {
            guard detail?.hasOwnActions != true, !MeetingState.hideDetails, Self.isChangePreview(command) else { return 0 }
            let wrapped = command.split(separator: "\n", omittingEmptySubsequences: false)
                .reduce(0) { $0 + max(1, ($1.count + 54) / 55) }
            return CGFloat(min(wrapped, 8)) * 15 + 14 + 8
        }

        /// Everything the card grows by beyond the plain one-line layout.
        @MainActor var extraHeight: CGFloat { (detail?.height ?? 0) + previewHeight }
    }

    var presentation: Presentation = .closed
    /// The shape's height follows this, set in its own faster transaction (Glance's height leads its
    /// width on open). Nil follows `presentation` (snapshots, tests).
    var heightPresentation: Presentation?
    var shownHeight: Presentation { heightPresentation ?? presentation }
    /// When the panel last opened (starts the glass bloom).
    var openedAt: Date?
    var sessions: [Session] = []
    var approval: Approval?
    /// Covered window frames while Zeus works behind. Nil when nothing is streaming.
    var workBehind: WorkBehindPreview?
    /// Before/after for a selection edit. Return accepts it.
    var selectionEdit: SelectionEdit?
    /// "Done" card in the peek after an agent finishes.
    var completion: AgentCompletion?
    /// Red card for a failed turn; shown in the peek until dismissed.
    var failure: Failure?
    /// "Welcome back" recap after Tony was away; the lowest-priority peek card.
    var recap: WelcomeRecap?
    /// The keyboard agent picker (shortcut, arrows, Return, Esc); nil when closed.
    var picker: AgentPicker?
    /// Incoming alerts from other apps: the glass capsule under the notch (see `AlertStack`).
    var alerts = AlertStack()
    /// The front alert, as the line the open action understands.
    var notificationLine: NotificationLine? {
        alerts.visible.first.map { NotificationLine(id: Int64($0.id) ?? 0, app: $0.appID, title: $0.title, detail: $0.body) }
    }
    /// The session the peek talks about when there is no approval.
    var peekSessionID: String?
    /// Sessions ZEUS runs itself (the browser agent) get a Stop button on their card.
    @ObservationIgnored var stopHandlers: [String: @MainActor () -> Void] = [:]

    /// Drives the halo colour and the peek's status word.
    var status: Status {
        if approval != nil { return .needsYou }
        if failure != nil || sessions.contains(where: { $0.status == .failed }) { return .failed }
        if sessions.contains(where: { $0.status == .needsYou }) { return .needsYou }
        if sessions.contains(where: { $0.status == .stalled }) { return .stalled }
        if let session = peekSession { return session.status }
        return sessions.contains(where: { $0.status == .working }) ? .working : .idle
    }

    /// Marks working sessions silent for `threshold` seconds as stalled. Returns the ones that just stalled.
    @discardableResult
    func checkStalls(now: Date, threshold: TimeInterval) -> [Session] {
        var stalled: [Session] = []
        for index in sessions.indices {
            let session = sessions[index]
            let next = AgentStall.afterCheck(session.status, lastEvent: session.lastEventAt, now: now, threshold: threshold)
            guard next != session.status else { continue }
            sessions[index].status = next
            sessions[index].reason = AgentStall.reason(silentFor: now.timeIntervalSince(session.lastEventAt))
            stalled.append(sessions[index])
        }
        return stalled
    }

    /// The session the picker has highlighted.
    var pickedSession: Session? {
        guard let picker, sessions.indices.contains(picker.index) else { return nil }
        return sessions[picker.index]
    }

    var peekSession: Session? {
        guard let id = peekSessionID else { return sessions.first }
        return sessions.first { $0.id == id }
    }
}
