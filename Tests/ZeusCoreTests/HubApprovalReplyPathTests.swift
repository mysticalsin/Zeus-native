import Foundation
import Testing
@testable import ZeusCore

/// One path: events step the session the chat page shows, a typed reply waits, and
/// Approve and Deny are the decisions that move that session or release the line.
@Suite("Hub approval reply path")
struct HubApprovalReplyPathTests {
    private func runningPath() -> HubApprovalReplyPath {
        var path = HubApprovalReplyPath(name: "Sample", sessionID: "row-1")
        path.apply(.announced)
        path.apply(.promptStarted)
        return path
    }

    @Test func eventsDriveTheSessionTheChatPageShows() {
        var path = HubApprovalReplyPath(name: "Sample", sessionID: "row-1")
        #expect(path.page(at: 0).statusWord == nil)
        #expect(path.page(at: 0).caption == "Sample, Not started")

        path.apply(.announced)
        #expect(path.page(at: 0).statusWord == "Announced")
        #expect(path.page(at: 0).caption == "Sample, Announced")
        #expect(path.session.clockPhase == .notStarted)

        path.apply(.promptStarted)
        #expect(path.page(at: 0).statusWord == "Running")
        #expect(path.page(at: 0).caption == "Sample, Running")
        #expect(path.session.clockPhase == .ticking)
        let generation = path.session.clockGeneration

        path.apply(.toolActivity)
        #expect(path.page(at: 0).statusWord == "Running")
        #expect(path.session.clockGeneration == generation)

        path.apply(.finished)
        #expect(path.page(at: 0).statusWord == "Done")
        #expect(path.session.clockPhase == .frozen)
        #expect(path.session.clockGeneration == generation)
        let done = path.session
        path.apply(.toolActivity)
        #expect(path.session == done)
        #expect(path.page(at: 0).caption == "Sample, Done")
    }

    @Test func aTypedReplyWaitsUntilApproveAndDenyKeepsTheDraft() {
        var path = runningPath()
        let asked = path.sendReply(
            "Ship the note",
            destination: "Terminal",
            canTakeText: true,
            trusted: true,
            at: 10
        )
        #expect(asked.asksInline)
        #expect(asked.typedLine == nil)
        let waiting = path.page(at: 10)
        #expect(waiting.statusWord == "Running")
        #expect(waiting.replyWaiting)
        #expect(waiting.draft == "Ship the note")
        #expect(waiting.inlineLine == "Ship the note")
        #expect(waiting.typedLine == nil)

        var untrusted = runningPath()
        let stillWaiting = untrusted.sendReply(
            "Ship the note",
            destination: "Terminal",
            canTakeText: true,
            trusted: false,
            at: 10
        )
        #expect(stillWaiting.asksInline)
        #expect(stillWaiting.typedLine == nil)
        #expect(untrusted.page(at: 10).replyWaiting)

        let denied = path.press(.deny, focus: nil, at: 12)
        #expect(denied.typedLine == nil)
        let kept = path.page(at: 12)
        #expect(kept.replyWaiting == false)
        #expect(kept.draft == "Ship the note")
        #expect(kept.inlineLine == nil)
        #expect(kept.typedLine == nil)
        #expect(kept.statusWord == "Running")
        #expect(path.gate.state.receipt == .notSent)

        var blocked = runningPath()
        let refused = blocked.sendReply(
            "Ship the note",
            destination: "Terminal",
            canTakeText: false,
            trusted: true,
            at: 1
        )
        #expect(refused.asksInline == false)
        #expect(refused.typedLine == nil)
        #expect(blocked.page(at: 1).inlineLine == nil)
        #expect(blocked.gate.state.status == .unsupported)

        var blank = runningPath()
        let empty = blank.sendReply(" \n\t ", destination: "Terminal", canTakeText: true, trusted: false, at: 1)
        #expect(empty.typedLine == nil)
        #expect(empty.asksInline == false)
        #expect(blank.gate.state.receipt == .typeSomethingFirst)

        var released = runningPath()
        _ = released.sendReply("Ship the note", destination: "Terminal", canTakeText: true, trusted: true, at: 10)
        let approved = released.press(.approve, focus: nil, at: 11)
        #expect(approved.typedLine == "Ship the note")
        #expect(released.page(at: 11).typedLine == "Ship the note")
        #expect(released.page(at: 11).replyWaiting == false)
        let again = released.press(.approve, focus: nil, at: 12)
        #expect(again.typedLine == nil)
        #expect(released.page(at: 12).typedLine == "Ship the note")

        var cancelled = runningPath()
        _ = cancelled.sendReply("Ship the note", destination: "Terminal", canTakeText: true, trusted: false, at: 10)
        let cancel = cancelled.press(.cancel, focus: nil, at: 11)
        #expect(cancel.typedLine == nil)
        #expect(cancelled.gate.state.status == .drafting)
        #expect(cancelled.gate.state.draft == "Ship the note")
        #expect(cancelled.gate.state.receipt == nil)
        #expect(cancelled.page(at: 11).typedLine == nil)
    }

    @Test func approveAndDenyAreRealDecisions() {
        var path = runningPath()
        let running = path.page(at: 0).statusWord
        let idle = path.decide(.approve)
        #expect(idle.verdict == nil)
        #expect(path.page(at: 0).statusWord == running)
        #expect(path.page(at: 0).showingApprovalID == nil)

        path.apply(.approvalRequested)
        #expect(path.page(at: 0).statusWord == "Needs approval")
        #expect(path.session.previous == .running)

        let first = path.decide(.request, request: HubApprovalRequest(id: "one", sessionID: "row-1"))
        #expect(first.verdict == nil)
        #expect(path.page(at: 0).showingApprovalID == "one")
        _ = path.decide(.request, request: HubApprovalRequest(id: "two", sessionID: "row-1"))
        #expect(path.page(at: 0).showingApprovalID == "one")
        #expect(path.approvals.waiting.map(\.id) == ["two"])

        let allowed = path.decide(.approve)
        #expect(allowed.verdict == .allow)
        #expect(allowed.closedID == "one")
        #expect(path.page(at: 0).approvalVerdict == .allow)
        #expect(path.page(at: 0).showingApprovalID == "two")
        #expect(path.page(at: 0).statusWord == "Needs approval")

        let denied = path.decide(.deny)
        #expect(denied.verdict == .deny)
        #expect(denied.closedID == "two")
        #expect(path.page(at: 0).approvalVerdict == .deny)
        #expect(path.page(at: 0).showingApprovalID == nil)
        #expect(path.page(at: 0).statusWord == "Running")
        #expect(path.session.previous == nil)

        path.apply(.approvalRequested)
        _ = path.decide(.request, request: HubApprovalRequest(id: "three", sessionID: "row-1"))
        let timedOut = path.decide(.timeout)
        #expect(timedOut.verdict == .deny)
        #expect(path.page(at: 0).statusWord == "Running")
        #expect(path.page(at: 0).typedLine == nil)
    }
}
