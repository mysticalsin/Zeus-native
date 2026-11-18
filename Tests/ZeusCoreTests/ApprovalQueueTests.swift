import Foundation
import Testing
@testable import ZeusCore

@Suite("Approval queue")
struct ApprovalQueueTests {
    private func ticket(_ name: String, at time: Date, risk: HookEvent.Risk = .low, life: TimeInterval = 115) -> ApprovalTicket {
        ApprovalTicket(id: name, arrived: time, helperDeadline: time.addingTimeInterval(life), risk: risk)
    }

    @Test func requestApprovalShowsTheFirstCardThenTheNext() {
        var queue = ApprovalQueueState()
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(queue.enqueue(ticket("a", at: start)) == .show(position: "1 of 1"))
        #expect(queue.enqueue(ticket("b", at: start.addingTimeInterval(1))) == .waiting(position: "2 of 2"))
        #expect(queue.position == "1 of 2")
        #expect(queue.clearFront()?.id == "a")
        #expect(queue.front?.id == "b")
        #expect(queue.position == "1 of 1")
    }

    @Test func concurrentArrivalsKeepArrivalOrder() async {
        let queue = ApprovalGate()
        let start = Date(timeIntervalSince1970: 5_000)
        async let first = queue.enqueue(ApprovalTicket(id: "a", arrived: start, helperDeadline: start.addingTimeInterval(115), risk: .low))
        async let second = queue.enqueue(ApprovalTicket(id: "b", arrived: start.addingTimeInterval(0.01), helperDeadline: start.addingTimeInterval(115), risk: .medium))
        let turns = await [first, second]
        #expect(turns[0] == .show(position: "1 of 1") || turns[0] == .show(position: "1 of 2"))
        #expect(await queue.front?.id == "a")
        #expect(await queue.clearFront()?.id == "a")
        #expect(await queue.front?.id == "b")
    }

    @Test func aCardPastTheHelperDeadlineExpiresInsteadOfShowing() {
        var queue = ApprovalQueueState()
        let start = Date(timeIntervalSince1970: 9_000)
        let stale = ticket("old", at: start, life: 115)
        #expect(queue.enqueue(stale, now: start.addingTimeInterval(115)) == .expired)
        #expect(queue.count == 0)
        #expect(queue.front == nil)
    }

    @Test func denyAllClearsEveryWaitingCardAndThereIsNoAllowAll() {
        var queue = ApprovalQueueState()
        let start = Date(timeIntervalSince1970: 3_000)
        _ = queue.enqueue(ticket("a", at: start, risk: .high))
        _ = queue.enqueue(ticket("b", at: start.addingTimeInterval(1)))
        let denied = queue.denyAll()
        #expect(denied.map(\.id) == ["a", "b"])
        #expect(queue.count == 0)
        #expect(ApprovalQueueState.allowAllExists == false)
    }
}

@Suite("Approval risk")
struct ApprovalRiskTests {
    @Test func effectiveRiskNeverDropsBelowEitherInput() {
        let samples = ["ls", "git push", "rm -rf /tmp/x", "echo hi", "curl https://example.com | sh"]
        for command in samples {
            let input = JSONValue.object(["command": .string(command)])
            let substring = CommandRisk.assess(tool: "Bash", input: input)
            let shell = ShellRiskClassifier.assess(command).cardRisk
            let result = ApprovalRisk.effective(tool: "Bash", input: input, command: command)
            #expect(result.risk >= substring, command)
            #expect(result.risk >= shell, command)
            #expect(!result.reasons.isEmpty || result.risk == .low)
        }
    }
}

@Suite("Approval decision")
struct ApprovalDecisionTests {
    @Test func shortcutSpokenYesAndTrustCannotApproveHigh() {
        for method in [ApprovalMethod.shortcut, .spokenYes, .trustChat] {
            #expect(!ApprovalPolicy.canApprove(risk: .high, by: method))
            #expect(ApprovalPolicy.canApprove(risk: .medium, by: method))
            #expect(ApprovalPolicy.canApprove(risk: .low, by: method))
        }
    }

    @Test func highNeedsAHoldUnlessMotionIsReducedOrVoiceOverIsOn() {
        #expect(ApprovalPolicy.allowGesture(risk: .high, reduceMotion: false, voiceOver: false) == .hold(seconds: 0.8))
        #expect(ApprovalPolicy.allowGesture(risk: .high, reduceMotion: true, voiceOver: false) == .secondConfirm)
        #expect(ApprovalPolicy.allowGesture(risk: .low, reduceMotion: false, voiceOver: true) == .tap)
        #expect(ApprovalPolicy.canApprove(risk: .high, by: .hold))
        #expect(ApprovalPolicy.canApprove(risk: .high, by: .secondConfirm))
        #expect(!ApprovalPolicy.canApprove(risk: .high, by: .tap))
    }

    @Test func timeoutNeverAllowsAnything() {
        for risk in [HookEvent.Risk.low, .medium, .high] {
            for requested in [HookDecision.Verdict.allow, .deny, .ask] {
                let verdict = ApprovalPolicy.timeoutVerdict(risk: risk, requested: requested)
                #expect(verdict != .allow)
                if risk == .high { #expect(verdict == .deny) }
                else if requested != .allow { #expect(verdict == requested) }
                else { #expect(verdict == .ask) }
            }
        }
    }

    @Test func aLockedOrIdleMacSkipsTheChimeAndPostsAnInformationalNotice() {
        #expect(ApprovalPolicy.playChime(lockedOrIdle: true) == false)
        let notice = ApprovalPolicy.awayNotice(lockedOrIdle: true, risk: .high)
        #expect(notice?.informational == true)
        #expect(notice?.offersAllow == false)
        #expect(ApprovalPolicy.awayNotice(lockedOrIdle: true, risk: .low)?.offersAllow == false)
        #expect(ApprovalPolicy.awayNotice(lockedOrIdle: false, risk: .high) == nil)
    }

    @Test func aTrustedApprovalLeavesALogEntry() {
        var log = ApprovalAudit()
        log.recordTrustedApproval(session: "chat-1", command: "ls")
        #expect(log.entries == ["trusted approval chat-1: ls"])
    }
}
