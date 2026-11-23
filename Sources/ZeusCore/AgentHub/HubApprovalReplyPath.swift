import Foundation

/// The session row the Chat tab shows. Events are the only thing that change the status word.
public struct HubChatSessionPage: Equatable, Sendable {
    public var name: String
    public var statusWord: String?
    public var clockPhase: HubClockPhase?
    public var replyWaiting: Bool
    public var draft: String
    public var typedLine: String?
    public var inlineLine: String?
    public var approvalVerdict: HubApprovalVerdict?
    public var showingApprovalID: String?

    public var caption: String {
        "\(name), \(statusWord ?? "Not started")"
    }

    public init(
        name: String,
        statusWord: String?,
        clockPhase: HubClockPhase?,
        replyWaiting: Bool,
        draft: String,
        typedLine: String?,
        inlineLine: String?,
        approvalVerdict: HubApprovalVerdict?,
        showingApprovalID: String?
    ) {
        self.name = name
        self.statusWord = statusWord
        self.clockPhase = clockPhase
        self.replyWaiting = replyWaiting
        self.draft = draft
        self.typedLine = typedLine
        self.inlineLine = inlineLine
        self.approvalVerdict = approvalVerdict
        self.showingApprovalID = showingApprovalID
    }
}

/// The reply-through-approval path for one selected session.
///
/// `apply` is the only way a session event changes the row the chat page shows.
/// A typed reply asks inline and types nothing. Approve is the only press that can
/// release the cleaned line. Deny, Cancel, Escape, and the timeout type nothing.
/// Approve and Deny on a queued permission are verdicts, and they step the session.
public struct HubApprovalReplyPath: Equatable, Sendable {
    public let name: String
    public let sessionID: String
    public private(set) var session: HubSessionState
    public private(set) var gate: HubReplyDispatch
    public private(set) var approvals: HubApprovalQueue

    private var pending = HubPendingReplyModel()
    private var canTakeText = false
    private var trusted = false
    private var lastVerdict: HubApprovalVerdict?
    private var lastTypedLine: String?

    public init(name: String, sessionID: String) {
        self.name = name
        self.sessionID = sessionID
        self.session = HubSessionState()
        var gate = HubReplyDispatch()
        _ = gate.bind(sessionID)
        self.gate = gate
        self.approvals = HubApprovalQueue()
    }

    /// Events drive the session. A pair that is not in the table leaves it unchanged.
    public mutating func apply(_ event: HubSessionEvent) {
        session = HubSessionMachine.next(session, event)
    }

    /// Send asks. It does not type, and trust does not skip the ask.
    @discardableResult
    public mutating func sendReply(
        _ text: String,
        destination: String,
        canTakeText: Bool,
        trusted: Bool,
        at now: TimeInterval
    ) -> HubReplyDispatch.Step {
        self.canTakeText = canTakeText
        self.trusted = trusted
        lastTypedLine = nil
        let step = gate.perform(
            .send,
            sessionID: sessionID,
            field: text,
            destinationCanTakeText: canTakeText,
            trusted: trusted
        )
        if step.asksInline {
            let deadline = now + HubPendingReplyModel.waitSeconds
            _ = pending.present(
                HubPendingReplyOffer(id: sessionID, destination: destination, draft: text),
                at: now,
                deadline: deadline
            )
        }
        return step
    }

    /// Approve releases one line. Deny, Cancel, Escape, and the timeout release none.
    /// A second Approve, and a press while the row is closed, type nothing.
    @discardableResult
    public mutating func press(
        _ action: HubPendingReplyAction,
        focus: HubPendingReplyFocus?,
        at now: TimeInterval
    ) -> HubReplyDispatch.Step {
        let verdict = pending.decide(action, id: sessionID, focus: focus, at: now)
        switch verdict {
        case .ignore:
            return .hold(gate.state)
        case .release:
            return record(gate.perform(
                .approved,
                sessionID: sessionID,
                field: gate.state.draft,
                destinationCanTakeText: canTakeText,
                trusted: trusted
            ))
        case .withhold(_, .deny):
            return record(gate.perform(
                .denied,
                sessionID: sessionID,
                field: gate.state.draft,
                destinationCanTakeText: canTakeText,
                trusted: trusted
            ))
        case .withhold(_, .cancel):
            return record(gate.cancel(sessionID: sessionID))
        case .withhold(_, .timeout):
            return record(gate.perform(
                .timedOut,
                sessionID: sessionID,
                field: gate.state.draft,
                destinationCanTakeText: canTakeText,
                trusted: trusted
            ))
        }
    }

    /// Approve, Deny, and timeout are verdicts. The session moves with that verdict.
    /// A queued request stays behind the one that is showing, then becomes the row.
    @discardableResult
    public mutating func decide(
        _ event: HubApprovalEvent,
        request: HubApprovalRequest? = nil
    ) -> HubApprovalOutcome {
        let previousShowing = approvals.showing?.id
        let outcome = HubDecision.approval(approvals, event, request: request)
        approvals = outcome.queue
        if let verdict = outcome.verdict {
            lastVerdict = verdict
            switch (event, verdict) {
            case (.approve, .allow), (.ask, .ask):
                apply(.approved)
            case (.deny, .deny):
                apply(.denied)
            case (.timeout, .deny):
                apply(.timedOut)
            default:
                break
            }
        }
        if let shown = approvals.showing?.id, shown != previousShowing {
            apply(.approvalRequested)
        }
        return outcome
    }

    public func page(at now: TimeInterval) -> HubChatSessionPage {
        HubChatSessionPage(
            name: name,
            statusWord: session.status.visibleWord,
            clockPhase: session.clockPhase,
            replyWaiting: gate.state.status == .awaitingDecision,
            draft: gate.state.draft,
            typedLine: lastTypedLine,
            inlineLine: pending.displayed(at: now)?.line,
            approvalVerdict: lastVerdict,
            showingApprovalID: approvals.showing?.id
        )
    }

    private mutating func record(_ step: HubReplyDispatch.Step) -> HubReplyDispatch.Step {
        if let line = step.typedLine {
            lastTypedLine = line
        }
        return step
    }
}
