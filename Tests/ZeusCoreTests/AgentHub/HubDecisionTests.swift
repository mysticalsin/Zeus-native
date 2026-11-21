import Foundation
import Testing
@testable import ZeusCore

/// The approval queue and the reply gate. The target table is the oracle.
/// A pair that is not in the table leaves the state as it was. A missing fact denies.
@Suite("Hub decision")
struct HubDecisionTests {
    @Test func aSecondApprovalQueuesAndApprovingTheFirstShowsTheSecond() {
        let first = HubApprovalRequest(id: "a", sessionID: "session-a")
        let second = HubApprovalRequest(id: "b", sessionID: "session-b")
        let third = HubApprovalRequest(id: "c", sessionID: "session-c")

        let idle = HubApprovalQueue()
        #expect(idle.phase == .idle)
        #expect(idle.showing == nil)
        #expect(idle.waiting.isEmpty)

        let showing = HubDecision.approval(idle, .request, request: first)
        #expect(showing.verdict == nil)
        #expect(showing.closedID == nil)
        #expect(showing.queue.phase == .showing)
        #expect(showing.queue.showing == first)
        #expect(showing.queue.waiting.isEmpty)

        let queued = HubDecision.approval(showing.queue, .request, request: second)
        #expect(queued.verdict == nil)
        #expect(queued.closedID == nil)
        #expect(queued.queue.phase == .queued)
        #expect(queued.queue.showing == first)
        #expect(queued.queue.waiting == [second])

        let deeper = HubDecision.approval(queued.queue, .request, request: third)
        #expect(deeper.verdict == nil)
        #expect(deeper.queue.showing == first)
        #expect(deeper.queue.waiting == [second, third])
        #expect(deeper.queue.phase == .queued)

        let approved = HubDecision.approval(deeper.queue, .approve)
        #expect(approved.verdict == .allow)
        #expect(approved.closedID == "a")
        #expect(approved.queue.phase == .queued)
        #expect(approved.queue.showing == second)
        #expect(approved.queue.waiting == [third])

        let secondVerdict = HubDecision.approval(approved.queue, .approve)
        #expect(secondVerdict.verdict == .allow)
        #expect(secondVerdict.closedID == "b")
        #expect(secondVerdict.queue.showing == third)
        #expect(secondVerdict.queue.waiting.isEmpty)
        #expect(secondVerdict.queue.phase == .showing)
    }

    @Test func denyAndTimeoutDenyThenShowTheNext() {
        let queued = queue(showing: "a", then: "b")

        let denied = HubDecision.approval(queued, .deny)
        #expect(denied.verdict == .deny)
        #expect(denied.closedID == "a")
        #expect(denied.queue.showing?.id == "b")
        #expect(denied.queue.waiting.isEmpty)
        #expect(denied.queue.phase == .showing)

        let timed = HubDecision.approval(queued, .timeout)
        #expect(timed.verdict == .deny)
        #expect(timed.closedID == "a")
        #expect(timed.queue.showing?.id == "b")
        #expect(timed.verdict != .allow)
        #expect(timed.verdict != .ask)
    }

    @Test func askIsAKeyboardVerdictAndNeverAnAllow() {
        let silent = queue(showing: "a", allowsAsk: false, then: "b")
        let ignored = HubDecision.approval(silent, .ask)
        #expect(ignored.verdict == nil)
        #expect(ignored.queue == silent)

        let askable = queue(showing: "a", allowsAsk: true, then: "b")
        let asked = HubDecision.approval(askable, .ask)
        #expect(asked.verdict == .ask)
        #expect(asked.closedID == "a")
        #expect(asked.queue.showing?.id == "b")
        #expect(asked.queue.waiting.isEmpty)
        #expect(asked.verdict != .allow)
    }

    @Test func approvalFailsClosed() {
        let live = queue(showing: "a", then: "b")

        let idleApprove = HubDecision.approval(HubApprovalQueue(), .approve)
        #expect(idleApprove.verdict == nil)
        #expect(idleApprove.queue == HubApprovalQueue())

        let waitingOnly = HubApprovalQueue(waiting: [HubApprovalRequest(id: "b", sessionID: "session-b")])
        let waitingApprove = HubDecision.approval(waitingOnly, .approve)
        #expect(waitingApprove.verdict == nil)
        #expect(waitingApprove.queue == waitingOnly)

        for event in [HubApprovalEvent.deny, .timeout, .ask, .showingClosed] {
            let outcome = HubDecision.approval(HubApprovalQueue(), event)
            #expect(outcome.verdict == nil)
            #expect(outcome.queue.phase == .idle)
        }

        // A live approval stays until a verdict. Closing it does not reveal the next and does not allow.
        let closed = HubDecision.approval(live, .showingClosed)
        #expect(closed.verdict == nil)
        #expect(closed.queue == live)

        let promoted = HubDecision.approval(waitingOnly, .showingClosed)
        #expect(promoted.verdict == nil)
        #expect(promoted.closedID == nil)
        #expect(promoted.queue.showing?.id == "b")
        #expect(promoted.queue.waiting.isEmpty)
        #expect(promoted.queue.phase == .showing)

        let blankID = HubDecision.approval(HubApprovalQueue(), .request, request: HubApprovalRequest(id: " ", sessionID: "session"))
        let blankSession = HubDecision.approval(HubApprovalQueue(), .request, request: HubApprovalRequest(id: "x", sessionID: " "))
        let missing = HubDecision.approval(HubApprovalQueue(), .request)
        #expect(blankID.queue.phase == .idle && blankID.verdict == nil)
        #expect(blankSession.queue == HubApprovalQueue() && blankSession.verdict == nil)
        #expect(missing.queue == HubApprovalQueue() && missing.verdict == nil)

        let duplicate = HubDecision.approval(live, .request, request: HubApprovalRequest(id: "a", sessionID: "other"))
        #expect(duplicate.queue == live)
        #expect(duplicate.verdict == nil)

        let smuggled = HubDecision.approval(HubApprovalQueue(), .approve, request: HubApprovalRequest(id: "a", sessionID: "session-a"))
        #expect(smuggled.queue.phase == .idle)
        #expect(smuggled.verdict == nil)

        let unboundShowing = HubApprovalQueue(showing: HubApprovalRequest(id: "a", sessionID: " "))
        let unboundVerdict = HubDecision.approval(unboundShowing, .approve)
        #expect(unboundVerdict.verdict == nil)
        #expect(unboundVerdict.queue == unboundShowing)

        let unboundWaiting = HubApprovalQueue(waiting: [HubApprovalRequest(id: " ", sessionID: "session")])
        let stuck = HubDecision.approval(unboundWaiting, .showingClosed)
        #expect(stuck.verdict == nil)
        #expect(stuck.queue == unboundWaiting)
    }

    @Test func approvalTableIsTotal() {
        for status in HubApprovalStatus.allCases {
            for event in HubApprovalEvent.allCases {
                for another in [false, true] {
                    for allowsAsk in [false, true] {
                        let step = HubDecision.approvalStep(
                            status, event, anotherIsShowing: another, allowsAsk: allowsAsk)
                        #expect(step == expectedApproval(status, event, anotherIsShowing: another, allowsAsk: allowsAsk))
                        if step.verdict == .allow {
                            #expect(status == .showing && event == .approve)
                        }
                        if event == .timeout {
                            #expect(step.verdict != .allow && step.verdict != .ask)
                        }
                    }
                }
            }
        }
    }

    @Test func aCapableReplyWaitsAndProducesNoScriptUntilApproved() {
        let drafted = HubDecision.reply(
            HubReplyState(),
            .textChanged,
            context: HubReplyContext(text: "  keep   going\n", destinationCanTakeText: true, trusted: false))
        #expect(drafted.state.status == .drafting)
        #expect(drafted.state.draft == "  keep   going\n")
        #expect(drafted.script == nil)
        #expect(drafted.asksApproval == false)

        let sent = HubDecision.reply(
            drafted.state,
            .send,
            context: HubReplyContext(destinationCanTakeText: true, trusted: false))
        #expect(sent.state.status == .awaitingDecision)
        #expect(sent.state.draft == "  keep   going\n")
        #expect(sent.state.script == nil)
        #expect(sent.script == nil)
        #expect(sent.asksApproval)
        #expect(sent.state.receipt == nil)

        let early = HubDecision.reply(sent.state, .scriptTyped, context: HubReplyContext(destinationCanTakeText: true))
        #expect(early.state == sent.state)
        #expect(early.script == nil)
        #expect(early.asksApproval == false)

        let approved = HubDecision.reply(sent.state, .approved)
        #expect(approved.state.status == .sending)
        #expect(approved.script == "keep going")
        #expect(approved.state.script == "keep going")
        #expect(approved.asksApproval == false)
        #expect(approved.state.draft == "  keep   going\n")

        let typed = HubDecision.reply(approved.state, .scriptTyped)
        #expect(typed.state.status == .idle)
        #expect(typed.state.draft == "")
        #expect(typed.state.script == nil)
        #expect(typed.state.receipt == .sent)
        #expect(typed.script == nil)
    }

    @Test func denyKeepsTheDraft() {
        let waiting = HubReplyState(status: .awaitingDecision, draft: "  keep going ")
        for event in [HubReplyEvent.denied, .timedOut] {
            let outcome = HubDecision.reply(
                waiting, event, context: HubReplyContext(destinationCanTakeText: true, trusted: true))
            #expect(outcome.state.status == .idle)
            #expect(outcome.state.draft == "  keep going ")
            #expect(outcome.state.receipt == .notSent)
            #expect(outcome.state.script == nil)
            #expect(outcome.script == nil)
            #expect(outcome.asksApproval == false)
        }
    }

    @Test func aDestinationThatCannotTakeTextNeverAsks() {
        let drafted = HubReplyState(status: .drafting, draft: "keep going")
        for trusted in [false, true] {
            let outcome = HubDecision.reply(
                drafted,
                .send,
                context: HubReplyContext(destinationCanTakeText: false, trusted: trusted))
            #expect(outcome.state.status == .unsupported)
            #expect(outcome.state.receipt == .openDestination)
            #expect(outcome.state.draft == "keep going")
            #expect(outcome.asksApproval == false)
            #expect(outcome.script == nil)
            #expect(outcome.state.script == nil)
        }
        let omitted = HubDecision.reply(drafted, .send)
        #expect(omitted.state.status == .unsupported)
        #expect(omitted.asksApproval == false)
        #expect(omitted.script == nil)
    }

    @Test func trustDoesNotSkipTheReplyApproval() {
        let drafted = HubReplyState(status: .drafting, draft: "keep going")
        let trusted = HubDecision.reply(
            drafted, .send, context: HubReplyContext(destinationCanTakeText: true, trusted: true))
        let plain = HubDecision.reply(
            drafted, .send, context: HubReplyContext(destinationCanTakeText: true, trusted: false))
        #expect(trusted.state.status == .awaitingDecision)
        #expect(trusted.script == nil)
        #expect(trusted.state.script == nil)
        #expect(trusted.asksApproval)
        #expect(trusted == plain)

        let approved = HubDecision.reply(
            trusted.state, .approved, context: HubReplyContext(destinationCanTakeText: true, trusted: true))
        #expect(approved.state.status == .sending)
        #expect(approved.script == "keep going")
        let approvedPlain = HubDecision.reply(trusted.state, .approved)
        #expect(approved == approvedPlain)
    }

    @Test func anEmptyReplyDoesNotAsk() {
        let drafted = HubReplyState(status: .drafting, draft: " \n\t ")
        let outcome = HubDecision.reply(
            drafted, .send, context: HubReplyContext(destinationCanTakeText: true, trusted: true))
        #expect(outcome.state.status == .idle)
        #expect(outcome.state.receipt == .typeSomethingFirst)
        #expect(outcome.state.draft == " \n\t ")
        #expect(outcome.asksApproval == false)
        #expect(outcome.script == nil)
        #expect(outcome.state.script == nil)
    }

    @Test func aFailedScriptKeepsTheDraftAndDropsTheLine() {
        let sending = HubReplyState(status: .sending, draft: "keep going", script: "keep going")
        let failed = HubDecision.reply(sending, .scriptFailed, context: HubReplyContext(trusted: true))
        #expect(failed.state.status == .failed)
        #expect(failed.state.draft == "keep going")
        #expect(failed.state.receipt == .openSession)
        #expect(failed.state.script == nil)
        #expect(failed.script == nil)
        #expect(failed.asksApproval == false)
    }

    @Test func theReleasedLineIsOneCleanedLine() {
        let weird = HubReplyState(status: .awaitingDecision, draft: "  run   the\ntests\r\nplease\u{7} ")
        let approved = HubDecision.reply(
            weird, .approved, context: HubReplyContext(destinationCanTakeText: true, trusted: true))
        #expect(approved.script == "run the tests please")
        #expect(approved.state.status == .sending)

        let huge = String(repeating: "a", count: 5_000)
        let long = HubDecision.reply(HubReplyState(status: .awaitingDecision, draft: huge), .approved)
        #expect(long.script?.count == 2_000)
        #expect(long.script == String(repeating: "a", count: 2_000))

        let empty = HubDecision.reply(HubReplyState(status: .awaitingDecision, draft: " \n "), .approved)
        #expect(empty.state.status == .awaitingDecision)
        #expect(empty.script == nil)
        #expect(empty.state.script == nil)
    }

    @Test func replyTableIsTotalAndFailClosed() {
        let states = [
            HubReplyState(status: .idle, draft: "kept", receipt: .notSent),
            HubReplyState(status: .drafting, draft: "  keep   going\n"),
            HubReplyState(status: .drafting, draft: " \n\t "),
            HubReplyState(status: .unsupported, draft: "keep going", receipt: .openDestination),
            HubReplyState(status: .awaitingDecision, draft: "  keep   going\n"),
            HubReplyState(status: .awaitingDecision, draft: " \n\t "),
            HubReplyState(status: .sending, draft: "  keep   going\n", script: "keep going"),
            HubReplyState(status: .sending, draft: "  keep   going\n", script: nil),
            HubReplyState(status: .failed, draft: "  keep   going\n", receipt: .openSession),
        ]
        let contexts = [
            HubReplyContext(text: "next", destinationCanTakeText: false, trusted: false),
            HubReplyContext(text: "next", destinationCanTakeText: true, trusted: false),
            HubReplyContext(text: "next", destinationCanTakeText: false, trusted: true),
            HubReplyContext(text: "next", destinationCanTakeText: true, trusted: true),
            HubReplyContext(),
        ]
        for state in states {
            for event in HubReplyEvent.allCases {
                for context in contexts {
                    let outcome = HubDecision.reply(state, event, context: context)
                    let expected = expectedReply(state, event, context: context)
                    #expect(outcome == expected)
                    if outcome.script != nil {
                        #expect(state.status == .awaitingDecision && event == .approved)
                    }
                    if outcome.asksApproval {
                        #expect(state.status == .drafting && event == .send)
                        #expect(context.destinationCanTakeText)
                        #expect(cleaned(state.draft) != nil)
                    }
                }
            }
        }
    }

    /// ZB-031. A typed reply waiting on approval has no cancel, so the draft stays stuck.
    @Test func aPendingTypedReplyCanBeCancelled() {
        let waiting = HubReplyState(status: .awaitingDecision, draft: "  keep   going\n")
        let context = HubReplyContext(destinationCanTakeText: true, trusted: true)
        let cancelled = HubDecision.reply(waiting, HubReplyCancel.cancel, context: context)
        #expect(cancelled.state.status == .drafting)
        #expect(cancelled.state.draft == "  keep   going\n")
        #expect(cancelled.state.receipt == nil)
        #expect(cancelled.state.script == nil)
        #expect(cancelled.script == nil)
        #expect(cancelled.asksApproval == false)
        #expect(cancelled != HubDecision.reply(waiting, .denied, context: context))
        #expect(cancelled != HubDecision.reply(waiting, .timedOut, context: context))
        #expect(cancelled != HubDecision.reply(waiting, .approved, context: context))

        let again = HubDecision.reply(cancelled.state, HubReplyCancel.cancel, context: context)
        #expect(again == cancelled)

        let resent = HubDecision.reply(cancelled.state, .send, context: context)
        #expect(resent.state.status == .awaitingDecision)
        #expect(resent.state.draft == "  keep   going\n")
        #expect(resent.asksApproval)
        #expect(resent.script == nil)
        #expect(resent.state.script == nil)
    }

    private func queue(showing id: String, allowsAsk: Bool = false, then next: String) -> HubApprovalQueue {
        let first = HubDecision.approval(
            HubApprovalQueue(),
            .request,
            request: HubApprovalRequest(id: id, sessionID: "session-\(id)", allowsAsk: allowsAsk))
        let second = HubDecision.approval(
            first.queue,
            .request,
            request: HubApprovalRequest(id: next, sessionID: "session-\(next)", allowsAsk: true))
        return second.queue
    }

    private func expectedApproval(
        _ status: HubApprovalStatus,
        _ event: HubApprovalEvent,
        anotherIsShowing: Bool,
        allowsAsk: Bool
    ) -> HubApprovalStep {
        switch (status, event, anotherIsShowing, allowsAsk) {
        case (.idle, .request, false, _):
            HubApprovalStep(status: .showing, verdict: nil)
        case (.idle, .request, true, _):
            HubApprovalStep(status: .queued, verdict: nil)
        case (.showing, .approve, _, _):
            HubApprovalStep(status: .idle, verdict: .allow)
        case (.showing, .deny, _, _), (.showing, .timeout, _, _):
            HubApprovalStep(status: .idle, verdict: .deny)
        case (.showing, .ask, _, true):
            HubApprovalStep(status: .idle, verdict: .ask)
        case (.queued, .showingClosed, _, _):
            HubApprovalStep(status: .showing, verdict: nil)
        default:
            HubApprovalStep(status: status, verdict: nil)
        }
    }

    /// One cleaned line, matching the gate: control characters become spaces, then the line is capped.
    private func cleaned(_ text: String) -> String? {
        let flat = text.unicodeScalars.map { scalar -> Character in
            scalar.value < 0x20 || scalar.value == 0x7F ? " " : Character(scalar)
        }
        let line = String(flat).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !line.isEmpty else { return nil }
        return String(line.prefix(2_000))
    }

    private func expectedReply(_ state: HubReplyState, _ event: HubReplyEvent, context: HubReplyContext) -> HubReplyOutcome {
        switch (state.status, event) {
        case (.idle, .textChanged):
            return HubReplyOutcome(
                state: HubReplyState(status: .drafting, draft: context.text, receipt: nil, script: nil),
                asksApproval: false,
                script: nil)
        case (.drafting, .send):
            if cleaned(state.draft) == nil {
                var next = state
                next.status = .idle
                next.receipt = .typeSomethingFirst
                next.script = nil
                return HubReplyOutcome(state: next, asksApproval: false, script: nil)
            }
            if !context.destinationCanTakeText {
                var next = state
                next.status = .unsupported
                next.receipt = .openDestination
                next.script = nil
                return HubReplyOutcome(state: next, asksApproval: false, script: nil)
            }
            var next = state
            next.status = .awaitingDecision
            next.receipt = nil
            next.script = nil
            return HubReplyOutcome(state: next, asksApproval: true, script: nil)
        case (.awaitingDecision, .denied), (.awaitingDecision, .timedOut):
            var next = state
            next.status = .idle
            next.receipt = .notSent
            next.script = nil
            return HubReplyOutcome(state: next, asksApproval: false, script: nil)
        case (.awaitingDecision, .approved):
            guard let line = cleaned(state.draft) else {
                return HubReplyOutcome(state: state, asksApproval: false, script: nil)
            }
            var next = state
            next.status = .sending
            next.receipt = nil
            next.script = line
            return HubReplyOutcome(state: next, asksApproval: false, script: line)
        case (.sending, .scriptTyped):
            guard state.script != nil else {
                return HubReplyOutcome(state: state, asksApproval: false, script: nil)
            }
            return HubReplyOutcome(
                state: HubReplyState(status: .idle, draft: "", receipt: .sent, script: nil),
                asksApproval: false,
                script: nil)
        case (.sending, .scriptFailed):
            var next = state
            next.status = .failed
            next.receipt = .openSession
            next.script = nil
            return HubReplyOutcome(state: next, asksApproval: false, script: nil)
        default:
            return HubReplyOutcome(state: state, asksApproval: false, script: nil)
        }
    }
}
