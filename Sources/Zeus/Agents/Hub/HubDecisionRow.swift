import Foundation
import ZeusCore

/// Red line for the inline decision row. The host fails until that row's accessibility label
/// matches the focus order in the experience contract: group header, row, Deny, Approve,
/// transcript, reply, Send, Open. Reduce Motion must request zero offset and scale 1.
/// Deny is never the default action.
enum HubDecisionRowTestHost {
    static let contract = "group header, row, Deny, Approve, transcript, reply, Send, Open"

    static func verify() {
        let label = HubDecisionRow.accessibilityContractLabel
        precondition(label == contract, "accessibility label \(label) does not match the PR 7 contract")
        precondition(HubDecisionRow.ownedAccessibilityLabels(showingApproval: true) == ["Deny", "Approve", "Reply", "Send"])
        precondition(HubDecisionRow.ownedAccessibilityLabels(showingApproval: false) == ["Reply", "Send"])
        let still = HubDecisionRow.reduceMotionRequest
        precondition(still.offset == 0 && still.scale == 1, "Reduce Motion must request zero offset and scale 1")
        let moving = HubDecisionRow.motion(reduceMotion: false)
        precondition(moving.offset == 8 && moving.scale == 0.985)
        precondition(HubDecisionRow.motion(reduceMotion: true) == still)
        precondition(HubDecisionRow.animates(reduceMotion: true) == false)
        precondition(HubDecisionRow.denyIsDefaultAction == false)
        precondition(HubDecisionRow.approveIsDefaultAction == false)
        precondition(HubDecisionRow.sendIsDefaultAction == false)
        precondition(HubDecisionRow.askIsButton == false)
        precondition(HubDecisionRow.countdown(12) == "12 s left, then it's denied.")
        precondition(HubDecisionRow.queuedHint(thisRowIsQueued: true, count: 1) == "Waiting behind the approval above. Buttons appear when it reaches the front.")
        precondition(HubDecisionRow.queuedHint(thisRowIsQueued: true, count: 2) == "2 waiting ahead. Waiting behind the approval above. Buttons appear when it reaches the front.")
        precondition(HubDecisionRow.queuedHint(thisRowIsQueued: false, count: 0) == nil)
        precondition(HubDecisionRow.queuedHint(thisRowIsQueued: false, count: 1) == "1 waiting")
        precondition(HubDecisionRow.queuedHint(thisRowIsQueued: false, count: 2) == "2 waiting")
        let priorities = HubFocusTarget.selectedApprovalOrder.map { HubDecisionFocus.priority($0) }
        precondition(zip(priorities, priorities.dropFirst()).allSatisfy { $0 > $1 })
        precondition(HubDecisionFocus.priority(.row) > HubDecisionFocus.toolPriority)
        precondition(HubDecisionFocus.toolPriority > HubDecisionFocus.bodyPriority)
        precondition(HubDecisionFocus.bodyPriority > HubDecisionFocus.priority(.deny))
        precondition(HubDecisionFocus.priority(.approve) > HubDecisionFocus.countdownPriority)
        precondition(HubDecisionFocus.countdownPriority > HubDecisionFocus.queuePriority)
        precondition(HubDecisionFocus.queuePriority > HubDecisionFocus.priority(.transcript))
        precondition(HubDecisionFocus.priority(.send) > HubDecisionFocus.receiptPriority)
        precondition(HubDecisionFocus.receiptPriority > HubDecisionFocus.priority(.open))
    }
}
