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

    @Test func aDoubleClickAcrossASwapDoesNotApproveTheNextCard() {
        let first = Box()
        let second = Box()
        let controller = NotchController()
        controller.monotonicNow = { 1_000 }
        controller.stageApprovals([
            card(id: "A", command: "first", box: first, onResolve: { controller.advanceAfterDisplayed("A") }),
            card(id: "B", command: "second", box: second),
        ])
        controller.model.approval?.appearedAt = Date().addingTimeInterval(-5)
        controller.activateApproval(kind: .card)
        controller.activateApproval(kind: .card)
        #expect(first.verdict == .allow)
        #expect(second.verdict == nil)
    }

    @Test func aVoiceOverActionAcrossASwapDoesNotApproveTheNextCard() {
        let first = Box()
        let second = Box()
        let controller = NotchController()
        controller.monotonicNow = { 1_000 }
        controller.stageApprovals([
            card(id: "A", command: "first", box: first, onResolve: { controller.advanceAfterDisplayed("A") }),
            card(id: "B", command: "second", box: second),
        ])
        controller.model.approval?.appearedAt = Date().addingTimeInterval(-5)
        controller.activateApproval(kind: .card)
        controller.model.approval?.activateAllow()
        #expect(first.verdict == .allow)
        #expect(second.verdict == nil)
    }

    @Test func aSwapLocksInputForEveryRiskIncludingHigh() {
        let first = Box()
        let second = Box()
        let controller = NotchController()
        controller.monotonicNow = { 1_000 }
        controller.approvalReduceMotion = { true }
        controller.stageApprovals([
            card(id: "A", command: "first", box: first, onResolve: { controller.advanceAfterDisplayed("A") }),
            card(id: "B", command: "second", box: second, risk: .high),
        ])
        controller.model.approval?.appearedAt = Date().addingTimeInterval(-5)
        controller.activateApproval(kind: .card)
        controller.activateApproval(kind: .card)
        #expect(first.verdict == .allow)
        #expect(second.verdict == nil)
        #expect(controller.model.approval?.allowGate.confirmVisible != true)
    }

    @Test func browsingAwayClearsAnArmedConfirm() {
        let controller = NotchController()
        controller.monotonicNow = { 1_000 }
        controller.approvalReduceMotion = { true }
        controller.stageApprovals([
            card(id: "A", command: "first", box: Box(), risk: .high),
            card(id: "B", command: "second", box: Box(), risk: .high),
        ])
        controller.model.approval?.appearedAt = Date().addingTimeInterval(-5)
        controller.activateApproval(kind: .card)
        #expect(controller.model.approval?.allowGate.confirmVisible == true)
        controller.browseApproval(by: 1)
        controller.browseApproval(by: 1)
        #expect(controller.model.approval?.id == "A")
        #expect(controller.model.approval?.allowGate.confirmVisible != true)
    }

    @Test func swappingBrowsingAndRemovalAnnounceTheCard() {
        let controller = NotchController()
        controller.stageApprovals([
            card(id: "A", command: "first", box: Box()),
            card(id: "B", command: "second", box: Box(), risk: .high),
        ])
        controller.browseApproval(by: 1)
        #expect(controller.lastApprovalAnnouncement == ApprovalCard.announcement(risk: .high, position: "2 of 2", outcome: nil))
        controller.advanceAfterDisplayed("B")
        #expect(controller.lastApprovalAnnouncement == ApprovalCard.announcement(risk: .low, position: "1 of 1", outcome: nil))
    }

    @Test func aPressThatSwapsCardsDoesNotFinishOnTheNextOne() {
        let first = Box()
        let second = Box()
        let controller = NotchController()
        controller.monotonicNow = { 1_000 }
        controller.stageApprovals([
            card(id: "A", command: "first", box: first),
            card(id: "B", command: "second", box: second),
        ])
        controller.beginApprovalHold()
        controller.browseApproval(by: 1)
        controller.monotonicNow = { 1_000 + 1 }
        controller.endApprovalHold(inside: true)
        #expect(first.verdict == nil)
        #expect(second.verdict == nil)
    }

    @Test func aRequestThatArrivesDuringDenyAllStaysQueued() {
        let boxes = [Box(), Box(), Box()]
        let arrived = Box()
        let controller = NotchController()
        controller.stageApprovals([
            card(id: "A", command: "first", box: boxes[0], onResolve: {
                controller.stageApprovals(controller.pendingApprovals + [card(id: "new", command: "later", box: arrived)])
            }),
            card(id: "B", command: "second", box: boxes[1]),
            card(id: "C", command: "third", box: boxes[2]),
        ])
        controller.denyEveryApproval()
        #expect(boxes.map(\.verdict) == [.deny, .deny, .deny])
        #expect(arrived.verdict == nil)
        #expect(controller.pendingApprovals.contains { $0.id == "new" } || controller.model.approval?.id == "new")
    }

    @Test func denyAllResolvesEveryQueuedCard() {
        let controller = NotchController()
        let boxes = [Box(), Box(), Box()]
        controller.stageApprovals((0..<3).map { index in
            card(id: "card-\(index)", command: "request \(index)", box: boxes[index])
        })
        controller.denyEveryApproval()
        #expect(boxes.map(\.verdict) == [.deny, .deny, .deny])
        #expect(controller.pendingApprovals.isEmpty)
        #expect(controller.model.approval == nil)
    }

    @Test func browsingResetsTheShortcutQuietPeriodAndRefreshesLabels() {
        let controller = NotchController()
        let past = Date().addingTimeInterval(-5)
        var cards = (0..<3).map { index in
            card(id: "card-\(index)", command: "request \(index)", box: Box())
        }
        for index in cards.indices { cards[index].appearedAt = past }
        controller.stageApprovals(cards)
        controller.browseApproval(by: 1)
        let shown = controller.model.approval
        #expect(shown?.position == "2 of 3")
        #expect(controller.pendingApprovals.map(\.position) == ["1 of 3", "2 of 3", "3 of 3"])
        #expect(!ApprovalCard.inputOpen(now: Date(), appearedAt: shown?.appearedAt ?? past))
    }

    @Test func voiceOverConfirmArmsTheHighPlanPath() {
        let (controller, _) = controller(reduceMotion: false)
        controller.approvalVoiceOver = { true }
        controller.commitDisplayedAnswers(inside: true)
        #expect(controller.model.approval?.allowGate.confirmVisible == true)
    }

    @Test func anOutsideReleaseAndADeniedReplyDropTheAnswer() {
        let (controller, box) = controller(reduceMotion: true)
        let detail = ApprovalDetail(kind: .questions([]), input: .object([:]), session: "s")
        controller.model.approval?.detail = detail
        detail.answer()
        controller.commitDisplayedAnswers(inside: false)
        #expect(detail.updatedInput == nil)
        #expect(!detail.answered)
        detail.answer()
        let denied = AgentEventServer.hookDecision(id: "event", verdict: .deny, detail: detail, session: "s")
        let asked = AgentEventServer.hookDecision(id: "event", verdict: .ask, detail: detail, session: "s")
        #expect(denied.updatedInput == nil)
        #expect(asked.updatedInput == nil)
        #expect(box.verdict == nil)
    }

    @Test func sendAnswersUsesTheDisplayedCommitPath() {
        let (controller, _) = controller(reduceMotion: true)
        let detail = ApprovalDetail(kind: .questions([]), input: .object([:]), session: "s")
        var card = controller.model.approval!
        card.detail = detail
        controller.stageApprovals([card])
        controller.model.approval?.commitAnswers(true)
        #expect(controller.model.approval?.allowGate.confirmVisible == true)
        #expect(detail.answered)
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

    private func card(id: String, command: String, box: Box, deny: Bool = false, risk: HookEvent.Risk = .low, onResolve: (() -> Void)? = nil) -> NotchModel.Approval {
        NotchModel.Approval(
            id: id, agent: "Claude", project: "zeus", tool: "Bash", command: command, risk: risk,
            position: "1 of 2", queueCount: 2,
            helperDeadlineMono: 9_000,
            allowGate: ApprovalAllowGate(risk: risk, itemID: id),
            deny: { if deny { box.verdict = .deny } },
            resolve: {
                if !deny || $0 == .allow { box.verdict = $0 }
                onResolve?()
            })
    }

    private final class Box { var verdict: HookDecision.Verdict? }
}
