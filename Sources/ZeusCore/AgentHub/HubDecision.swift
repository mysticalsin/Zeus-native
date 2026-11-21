import Foundation

/// The approval queue and the reply gate. A state and an event go in, and the next state comes out.
/// A pair that is not in the target table leaves the state unchanged. A missing fact denies.
/// Cancel is its own event. It is neither an approval nor a denial.
/// Nothing here types a line or draws a button.

public enum HubDecision {
    /// One request's row. A missing pair returns `status` and no verdict.
    /// Timeout denies. Ask is a verdict only when the request allows it. Trust is not an input.
    public static func approvalStep(
        _ status: HubApprovalStatus,
        _ event: HubApprovalEvent,
        anotherIsShowing: Bool = false,
        allowsAsk: Bool = false
    ) -> HubApprovalStep {
        switch (status, event) {
        case (.idle, .request) where !anotherIsShowing:
            return HubApprovalStep(status: .showing)
        case (.idle, .request) where anotherIsShowing:
            return HubApprovalStep(status: .queued)
        case (.showing, .approve):
            return HubApprovalStep(status: .idle, verdict: .allow)
        case (.showing, .deny), (.showing, .timeout):
            return HubApprovalStep(status: .idle, verdict: .deny)
        case (.showing, .ask) where allowsAsk:
            return HubApprovalStep(status: .idle, verdict: .ask)
        case (.queued, .showingClosed):
            return HubApprovalStep(status: .showing)
        default:
            return HubApprovalStep(status: status)
        }
    }

    /// One live approval, then the ones waiting behind it. A verdict names the one that was showing.
    /// A queued request is not decided. Closing the live one without a verdict leaves it showing.
    public static func approval(
        _ queue: HubApprovalQueue,
        _ event: HubApprovalEvent,
        request: HubApprovalRequest? = nil
    ) -> HubApprovalOutcome {
        switch event {
        case .request:
            return enqueue(queue, request)
        case .approve, .deny, .timeout, .ask:
            return decide(queue, event)
        case .showingClosed:
            return revealIfNothingIsShowing(queue)
        }
    }

    /// A typed reply. Trust does not skip the approval. A destination that cannot take text never asks.
    /// The script line is absent until the reply is approved, and a failed script drops it.
    /// A reply that is waiting returns to drafting only through `HubReplyCancel`.
    public static func reply(
        _ state: HubReplyState,
        _ event: HubReplyEvent,
        context: HubReplyContext = HubReplyContext()
    ) -> HubReplyOutcome {
        switch (state.status, event) {
        case (.idle, .textChanged):
            return HubReplyOutcome(state: HubReplyState(status: .drafting, draft: context.text))
        case (.drafting, .send):
            return send(state, context)
        case (.awaitingDecision, .denied), (.awaitingDecision, .timedOut):
            var next = state
            next.status = .idle
            next.receipt = .notSent
            next.script = nil
            return HubReplyOutcome(state: next)
        case (.awaitingDecision, .approved):
            guard let line = cleanedLine(state.draft) else { return .unchanged(state) }
            var next = state
            next.status = .sending
            next.receipt = nil
            next.script = line
            return HubReplyOutcome(state: next, script: line)
        case (.sending, .scriptTyped):
            guard state.script != nil else { return .unchanged(state) }
            return HubReplyOutcome(state: HubReplyState(status: .idle, draft: "", receipt: .sent))
        case (.sending, .scriptFailed):
            var next = state
            next.status = .failed
            next.receipt = .openSession
            next.script = nil
            return HubReplyOutcome(state: next)
        default:
            return .unchanged(state)
        }
    }

    /// Cancel a reply that is waiting on approval. The draft stays editable.
    /// Trust and the destination are not read, so this step cannot approve or deny.
    /// A second cancel, and a cancel from any other status, leaves the state as it is.
    public static func reply(
        _ state: HubReplyState,
        _ event: HubReplyCancel,
        context _: HubReplyContext = HubReplyContext()
    ) -> HubReplyOutcome {
        switch event {
        case .cancel:
            guard state.status == .awaitingDecision else { return .unchanged(state) }
            var next = state
            next.status = .drafting
            next.receipt = nil
            next.script = nil
            return HubReplyOutcome(state: next)
        }
    }

    /// One line, control characters as spaces, capped at 2,000. Nil when nothing is left.
    static func cleanedLine(_ text: String) -> String? {
        let flat = text.unicodeScalars.map { scalar -> Character in
            scalar.value < 0x20 || scalar.value == 0x7F ? " " : Character(scalar)
        }
        let line = String(flat).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !line.isEmpty else { return nil }
        return String(line.prefix(2_000))
    }

    private static func enqueue(_ queue: HubApprovalQueue, _ request: HubApprovalRequest?) -> HubApprovalOutcome {
        guard let request, isBound(request) else { return .unchanged(queue) }
        if queue.showing?.id == request.id || queue.waiting.contains(where: { $0.id == request.id }) {
            return .unchanged(queue)
        }
        let anotherIsShowing = queue.showing != nil || !queue.waiting.isEmpty
        let step = approvalStep(.idle, .request, anotherIsShowing: anotherIsShowing, allowsAsk: false)
        var next = queue
        if step.status == .showing, step.verdict == nil, queue.showing == nil, queue.waiting.isEmpty {
            next.showing = request
        } else if step.status == .queued, step.verdict == nil {
            next.waiting.append(request)
        } else {
            return .unchanged(queue)
        }
        return HubApprovalOutcome(queue: next)
    }

    private static func decide(_ queue: HubApprovalQueue, _ event: HubApprovalEvent) -> HubApprovalOutcome {
        guard let showing = queue.showing, isBound(showing) else { return .unchanged(queue) }
        let step = approvalStep(.showing, event, anotherIsShowing: false, allowsAsk: showing.allowsAsk)
        guard let verdict = step.verdict, step.status == .idle else { return .unchanged(queue) }
        switch (event, verdict) {
        case (.approve, .allow), (.deny, .deny), (.timeout, .deny), (.ask, .ask):
            break
        default:
            return .unchanged(queue)
        }
        var next = queue
        next.showing = nil
        if !next.waiting.isEmpty, !reveal(&next) { return .unchanged(queue) }
        return HubApprovalOutcome(queue: next, verdict: verdict, closedID: showing.id)
    }

    private static func revealIfNothingIsShowing(_ queue: HubApprovalQueue) -> HubApprovalOutcome {
        guard queue.showing == nil else { return .unchanged(queue) }
        var next = queue
        guard reveal(&next) else { return .unchanged(queue) }
        return HubApprovalOutcome(queue: next)
    }

    /// Moves the first queued request into the showing slot. The slot must already be empty.
    /// A request that is not bound to a session stays queued and is not shown.
    private static func reveal(_ queue: inout HubApprovalQueue) -> Bool {
        guard queue.showing == nil, let next = queue.waiting.first, isBound(next) else { return false }
        let step = approvalStep(.queued, .showingClosed, anotherIsShowing: false, allowsAsk: false)
        guard step.status == .showing, step.verdict == nil else { return false }
        queue.showing = queue.waiting.removeFirst()
        return true
    }

    private static func isBound(_ request: HubApprovalRequest) -> Bool {
        !request.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !request.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func send(_ state: HubReplyState, _ context: HubReplyContext) -> HubReplyOutcome {
        guard cleanedLine(state.draft) != nil else {
            var next = state
            next.status = .idle
            next.receipt = .typeSomethingFirst
            next.script = nil
            return HubReplyOutcome(state: next)
        }
        // Trust-this-chat does not cover a typed reply. The flag is not read.
        guard context.destinationCanTakeText else {
            var next = state
            next.status = .unsupported
            next.receipt = .openDestination
            next.script = nil
            return HubReplyOutcome(state: next)
        }
        var next = state
        next.status = .awaitingDecision
        next.receipt = nil
        next.script = nil
        return HubReplyOutcome(state: next, asksApproval: true)
    }
}

/// A permission request waiting on a person. Ask does nothing unless `allowsAsk` is set.
public struct HubApprovalRequest: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var sessionID: String
    public var allowsAsk: Bool

    public init(id: String, sessionID: String, allowsAsk: Bool = false) {
        self.id = id
        self.sessionID = sessionID
        self.allowsAsk = allowsAsk
    }
}

/// The live approval, then the requests behind it. `phase` is idle when both are empty.
public struct HubApprovalQueue: Equatable, Sendable {
    public var showing: HubApprovalRequest?
    public var waiting: [HubApprovalRequest]

    public init(showing: HubApprovalRequest? = nil, waiting: [HubApprovalRequest] = []) {
        self.showing = showing
        self.waiting = waiting
    }

    public var phase: HubApprovalStatus {
        switch (showing == nil, waiting.isEmpty) {
        case (true, true): .idle
        case (false, true): .showing
        case (_, false): .queued
        }
    }
}

/// The next status of one approval, and the verdict when that row decides.
public struct HubApprovalStep: Equatable, Sendable {
    public var status: HubApprovalStatus
    public var verdict: HubApprovalVerdict?

    public init(status: HubApprovalStatus, verdict: HubApprovalVerdict? = nil) {
        self.status = status
        self.verdict = verdict
    }
}

/// The queue after one event. `verdict` is set only for the approval that was showing.
public struct HubApprovalOutcome: Equatable, Sendable {
    public var queue: HubApprovalQueue
    public var verdict: HubApprovalVerdict?
    public var closedID: String?

    public init(queue: HubApprovalQueue, verdict: HubApprovalVerdict? = nil, closedID: String? = nil) {
        self.queue = queue
        self.verdict = verdict
        self.closedID = closedID
    }

    static func unchanged(_ queue: HubApprovalQueue) -> HubApprovalOutcome {
        HubApprovalOutcome(queue: queue)
    }
}

/// Where a typed reply is, including the draft and the line a script may type.
public struct HubReplyState: Equatable, Sendable {
    public var status: HubReplyStatus
    public var draft: String
    public var receipt: HubReplyReceipt?
    /// The cleaned line released by approval. Nil until then, and nil again after the script result.
    public var script: String?
    /// The app and tty shown on the pending reply. Nil until the reply asks.
    public var target: HubReplyTarget?

    public init(
        status: HubReplyStatus = .idle,
        draft: String = "",
        receipt: HubReplyReceipt? = nil,
        script: String? = nil,
        target: HubReplyTarget? = nil
    ) {
        self.status = status
        self.draft = draft
        self.receipt = receipt
        self.script = script
        self.target = target
    }
}

/// Cancel while a typed reply is waiting. It is not an approval verdict.
public enum HubReplyCancel: String, CaseIterable, Codable, Equatable, Hashable, Sendable, HubStoredLabel {
    case cancel
}

/// Facts the reply gate is told. An unknown destination cannot take text. Trust never skips the approval.
public struct HubReplyContext: Equatable, Sendable {
    public var text: String
    public var destinationCanTakeText: Bool
    public var trusted: Bool
    public var target: HubReplyTarget?
    public var foreground: HubReplyForeground.Verdict?

    public init(
        text: String = "",
        destinationCanTakeText: Bool = false,
        trusted: Bool = false,
        target: HubReplyTarget? = nil,
        foreground: HubReplyForeground.Verdict? = nil
    ) {
        self.text = text
        self.destinationCanTakeText = destinationCanTakeText
        self.trusted = trusted
        self.target = target
        self.foreground = foreground
    }
}

/// The reply after one event. `script` is the line this step released, and only an approval releases one.
public struct HubReplyOutcome: Equatable, Sendable {
    public var state: HubReplyState
    public var asksApproval: Bool
    public var script: String?

    public init(state: HubReplyState, asksApproval: Bool = false, script: String? = nil) {
        self.state = state
        self.asksApproval = asksApproval
        self.script = script
    }

    static func unchanged(_ state: HubReplyState) -> HubReplyOutcome {
        HubReplyOutcome(state: state)
    }
}
