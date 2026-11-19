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
        #expect(await queue.clearFront(id: "a")?.id == "a")
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
            #expect(result.risk >= substring, Comment(rawValue: command))
            #expect(result.risk >= shell, Comment(rawValue: command))
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

    @Test func aPlainActivationDoesNotAllowHigh() {
        let start = Date(timeIntervalSince1970: 4_000)
        var high = ApprovalAllowGate(risk: .high)
        #expect(high.activate(now: start) == nil)
        #expect(high.releaseHold(now: start.addingTimeInterval(0.2)) == nil)
        var again = ApprovalAllowGate(risk: .high)
        #expect(again.activate(now: start) == nil)
        #expect(again.releaseHold(now: start.addingTimeInterval(0.8)) == .allow)
        var reduced = ApprovalAllowGate(risk: .high, reduceMotion: true)
        #expect(reduced.activate(now: start) == nil)
        #expect(reduced.activate(now: start) == .allow)
        var spoken = ApprovalAllowGate(risk: .high, voiceOver: true)
        #expect(spoken.activate(now: start) == nil)
        #expect(spoken.activate(now: start) == .allow)
        var low = ApprovalAllowGate(risk: .low)
        var medium = ApprovalAllowGate(risk: .medium)
        #expect(low.activate(now: start) == .allow)
        #expect(medium.activate(now: start) == .allow)
    }

    @Test func shellHighBeatsANormalSubstringAndBlocksTheShortcut() {
        let command = "echo hi > /tmp/out"
        let input = JSONValue.object(["command": .string(command)])
        #expect(CommandRisk.assess(tool: "Bash", input: input) != .high)
        #expect(ShellRiskClassifier.assess(command).cardRisk == .high)
        let card = ApprovalRisk.effective(tool: "Bash", input: input, command: command)
        #expect(card.risk == .high)
        #expect(HookClientInput.effectiveRisk(claimed: .low, tool: "Bash", input: input) == .high)
        #expect(!ApprovalPolicy.canApprove(risk: card.risk, by: .shortcut))
        #expect(!ApprovalPolicy.canApprove(risk: card.risk, by: .spokenYes))
        #expect(!ApprovalPolicy.canApprove(risk: card.risk, by: .trustChat))
    }
}

@Suite("Approval expiry")
struct ApprovalExpiryTests {
    @Test func aRequestOlderThanTheHelperDeadlineCannotBeApproved() async {
        let start = Date(timeIntervalSince1970: 8_000)
        let clock = ApprovalClock(start)
        let gate = ApprovalGate(now: { clock.date })
        let stale = ApprovalTicket(id: "old", arrived: start, helperDeadline: start.addingTimeInterval(115), risk: .low)
        clock.date = start.addingTimeInterval(116)
        #expect(await gate.enqueue(stale) == .expired)
        #expect(await gate.front == nil)
        #expect(await gate.permits("old") == false)
    }

    @Test func clearFrontIgnoresADifferentIdAndADuplicateIdIsRejected() async {
        let start = Date(timeIntervalSince1970: 2_000)
        let gate = ApprovalGate(now: { start })
        let first = ApprovalTicket(id: "a", arrived: start, helperDeadline: start.addingTimeInterval(115), risk: .low)
        let second = ApprovalTicket(id: "b", arrived: start.addingTimeInterval(1), helperDeadline: start.addingTimeInterval(115), risk: .low)
        #expect(await gate.enqueue(first) == .show(position: "1 of 1"))
        #expect(await gate.enqueue(second) == .waiting(position: "2 of 2"))
        #expect(await gate.enqueue(first) == .duplicate)
        #expect(await gate.clearFront(id: "b") == nil)
        #expect(await gate.front?.id == "a")
        #expect(await gate.clearFront(id: "a")?.id == "a")
        #expect(await gate.front?.id == "b")
    }
}

@Suite("Approval audit")
struct ApprovalAuditTests {
    @Test func theLogDropsTheOldestAndStripsControlsFromEveryDecision() {
        var log = ApprovalAudit()
        log.record(kind: .card, session: "s\n1", command: "ls\u{0007}", verdict: "deny")
        log.record(kind: .shortcut, session: "s", command: "ls", verdict: "allow")
        log.record(kind: .voice, session: "s", command: "ls", verdict: "deny")
        log.record(kind: .timeout, session: "s", command: "ls", verdict: "deny")
        #expect(log.entries[0] == "card s1: ls deny")
        #expect(log.entries.map { $0.split(separator: " ").first.map(String.init) } == ["card", "shortcut", "voice", "timeout"])
        for index in 0..<ApprovalAudit.capacity {
            log.record(kind: .card, session: "s", command: "c\(index)", verdict: "deny")
        }
        #expect(log.entries.count == ApprovalAudit.capacity)
        #expect(log.entries.first?.contains("c0") == true)
        #expect(log.entries.contains { $0.contains("ls") } == false)
    }
}

private final class ApprovalClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}
