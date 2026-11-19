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

    private final class Box { var verdict: HookDecision.Verdict? }
}
