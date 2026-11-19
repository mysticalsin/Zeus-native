import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// High-risk allow through the controller: the button, the shortcut, and a spoken yes.
@MainActor @Suite("High approval paths") struct ApprovalHighPathTests {
    private func controller(risk: HookEvent.Risk = .high, reduceMotion: Bool = false) -> (NotchController, Box) {
        let controller = NotchController()
        controller.monotonicNow = { 1_000 }
        controller.approvalReduceMotion = { reduceMotion }
        controller.approvalVoiceOver = { false }
        let box = Box()
        controller.model.approval = NotchModel.Approval(
            id: "item", agent: "Claude", project: "zeus", tool: "Bash", command: "rm -rf /tmp/x", risk: risk,
            helperDeadlineMono: 9_000,
            allowGate: ApprovalAllowGate(risk: risk, itemID: "item"),
            resolve: { box.verdict = $0 })
        return (controller, box)
    }

    @Test func browsingMakesAllowAndDenyActOnTheDisplayedRequest() {
        let first = Box()
        let second = Box()
        let controller = NotchController()
        controller.monotonicNow = { 1_000 }
        controller.approvalReduceMotion = { false }
        controller.approvalVoiceOver = { false }
        controller.stageApprovals([
            card(id: "front", command: "first", box: first),
            card(id: "shown", command: "second", box: second),
        ])
        controller.browseApproval(by: 1)
        #expect(controller.model.approval?.id == "shown")
        #expect(controller.model.approval?.position == "2 of 2")
        controller.activateApproval(kind: .card)
        #expect(second.verdict == .allow)
        #expect(first.verdict == nil)
        let denyFirst = Box()
        let denySecond = Box()
        controller.stageApprovals([
            card(id: "front", command: "first", box: denyFirst, deny: true),
            card(id: "shown", command: "second", box: denySecond, deny: true),
        ])
        controller.browseApproval(by: 1)
        controller.model.approval?.deny()
        #expect(denySecond.verdict == .deny)
        #expect(denyFirst.verdict == nil)
    }

    @Test func aHighAnswerIsSentOnceTheGateAllows() {
        let (controller, box) = controller(reduceMotion: true)
        let detail = ApprovalDetail(kind: .questions([]), input: .object([:]), session: "s")
        controller.model.approval?.detail = detail
        controller.commitDisplayedAnswers(inside: true)
        #expect(detail.answered)
        #expect(box.verdict == nil)
        controller.monotonicNow = { 1_000 + 0.4 }
        controller.commitDisplayedAnswers(inside: true)
        #expect(box.verdict == .allow)
        #expect(detail.updatedInput != nil)
    }

    @Test func browseApprovalMovesWithinTheQueue() {
        let (controller, _) = controller()
        controller.model.approval?.queueCount = 3
        controller.browseApproval(by: 1)
        #expect(controller.model.approval?.queueIndex == 1)
        controller.browseApproval(by: 5)
        #expect(controller.model.approval?.queueIndex == 2)
        controller.browseApproval(by: -1)
        #expect(controller.model.approval?.queueIndex == 1)
    }

    @Test func aShortcutAndASpokenYesNeverAllowHigh() {
        let (controller, box) = controller(reduceMotion: true)
        controller.activateApproval(kind: .shortcut)
        controller.activateApproval(kind: .shortcut)
        controller.activateApproval(kind: .voice)
        controller.activateApproval(kind: .voice)
        #expect(box.verdict == nil)
        #expect(controller.model.approval?.allowGate.confirmVisible == false)
    }

    @Test func theOnScreenConfirmAllowsOnlyInsideItsWindow() {
        let (controller, box) = controller(reduceMotion: true)
        controller.activateApproval(kind: .card)
        #expect(box.verdict == nil)
        #expect(controller.model.approval?.allowGate.confirmVisible == true)
        controller.monotonicNow = { 1_000 + 0.2 }
        controller.activateApproval(kind: .card)
        #expect(box.verdict == nil)
        controller.monotonicNow = { 1_000 + 0.4 }
        controller.activateApproval(kind: .card)
        #expect(box.verdict == .allow)
    }

    @Test func aTimeoutOrATrustedKindDoesNotAllow() {
        let (controller, box) = controller(risk: .low)
        controller.activateApproval(kind: .timeout)
        controller.activateApproval(kind: .trusted)
        #expect(box.verdict == nil)
    }

    @Test func anAllowAfterSleepPastTheDeadlineIsRefused() {
        let (controller, box) = controller()
        controller.monotonicNow = { 9_000 }
        controller.activateApproval(kind: .card)
        #expect(box.verdict == .deny)
    }

    @Test func aReleaseOutsideTheButtonDoesNotAllow() {
        let (controller, box) = controller()
        controller.beginApprovalHold()
        controller.monotonicNow = { 1_000 + 0.8 }
        controller.endApprovalHold(inside: false)
        #expect(box.verdict == nil)
        #expect(controller.model.approval?.allowGate.holdingSince == nil)
        controller.beginApprovalHold()
        controller.monotonicNow = { 2_000 }
        controller.endApprovalHold(inside: true)
        #expect(box.verdict == .allow)
    }

    private func card(id: String, command: String, box: Box, deny: Bool = false) -> NotchModel.Approval {
        NotchModel.Approval(
            id: id, agent: "Claude", project: "zeus", tool: "Bash", command: command, risk: .low,
            position: "1 of 2", queueCount: 2,
            helperDeadlineMono: 9_000,
            allowGate: ApprovalAllowGate(risk: .low, itemID: id),
            deny: { if deny { box.verdict = .deny } },
            resolve: { if !deny || $0 == .allow { box.verdict = $0 } })
    }

    private final class Box { var verdict: HookDecision.Verdict? }
}
