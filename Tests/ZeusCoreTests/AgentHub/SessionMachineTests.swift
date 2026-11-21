import Foundation
import Testing
@testable import ZeusCore

/// The session table is the oracle. A pair that is not in it leaves the state unchanged.
@Suite("Session machine")
struct SessionMachineTests {
    private struct Expectation: Sendable {
        var status: HubSessionStatus
        var previous: HubSessionStatus?
        var clockGeneration: Int
    }

    /// Every pair starts here, so a transition that forgets `previous` or the clock cannot hide.
    /// Generation 5 is already ticking. `previous` is waiting for input, which is not the running default.
    private func seed(_ status: HubSessionStatus) -> HubSessionState {
        HubSessionState(status: status, clockGeneration: 5, previous: .waitingForInput)
    }

    /// Rows of the session table. Clock start and restart add one to the generation.
    /// Ending or a first announcement clears the generation and `previous`.
    private let table: [HubSessionStatus: [HubSessionEvent: Expectation]] = [
        .absent: [
            .announced: Expectation(status: .loading, previous: nil, clockGeneration: 0),
        ],
        .loading: [
            .promptStarted: Expectation(status: .running, previous: .waitingForInput, clockGeneration: 6),
            .failed: Expectation(status: .error(.failed), previous: .waitingForInput, clockGeneration: 5),
            .quietForTheStallLimit: Expectation(status: .error(.quiet), previous: .waitingForInput, clockGeneration: 5),
            .ended: Expectation(status: .absent, previous: nil, clockGeneration: 0),
        ],
        .running: [
            .toolActivity: Expectation(status: .running, previous: .waitingForInput, clockGeneration: 5),
            .questionAsked: Expectation(status: .waitingForInput, previous: .waitingForInput, clockGeneration: 5),
            .approvalRequested: Expectation(status: .needsApproval, previous: .running, clockGeneration: 5),
            .finished: Expectation(status: .done, previous: .waitingForInput, clockGeneration: 5),
            .failed: Expectation(status: .error(.failed), previous: .waitingForInput, clockGeneration: 5),
            .quietForTheStallLimit: Expectation(status: .error(.quiet), previous: .waitingForInput, clockGeneration: 5),
            .ended: Expectation(status: .absent, previous: nil, clockGeneration: 0),
        ],
        .waitingForInput: [
            .answerAccepted: Expectation(status: .running, previous: .waitingForInput, clockGeneration: 5),
            .approvalRequested: Expectation(status: .needsApproval, previous: .waitingForInput, clockGeneration: 5),
            .failed: Expectation(status: .error(.failed), previous: .waitingForInput, clockGeneration: 5),
            .finished: Expectation(status: .done, previous: .waitingForInput, clockGeneration: 5),
            .ended: Expectation(status: .absent, previous: nil, clockGeneration: 0),
        ],
        .needsApproval: [
            .approved: Expectation(status: .waitingForInput, previous: nil, clockGeneration: 5),
            .denied: Expectation(status: .waitingForInput, previous: nil, clockGeneration: 5),
            .timedOut: Expectation(status: .waitingForInput, previous: nil, clockGeneration: 5),
            .failed: Expectation(status: .error(.failed), previous: nil, clockGeneration: 5),
            .ended: Expectation(status: .absent, previous: nil, clockGeneration: 0),
        ],
        .done: [
            .promptStarted: Expectation(status: .running, previous: .waitingForInput, clockGeneration: 6),
            .ended: Expectation(status: .absent, previous: nil, clockGeneration: 0),
        ],
        .error(.quiet): [
            .activity: Expectation(status: .running, previous: .waitingForInput, clockGeneration: 5),
            .promptStarted: Expectation(status: .running, previous: .waitingForInput, clockGeneration: 6),
            .ended: Expectation(status: .absent, previous: nil, clockGeneration: 0),
        ],
        .error(.failed): [
            .promptStarted: Expectation(status: .running, previous: .waitingForInput, clockGeneration: 6),
            .dismissed: Expectation(status: .done, previous: .waitingForInput, clockGeneration: 5),
            .ended: Expectation(status: .absent, previous: nil, clockGeneration: 0),
        ],
    ]

    @Test func quietStallFreezesTheClockAndOnlyAQuietErrorReturnsOnActivity() {
        let loading = HubSessionMachine.next(HubSessionState(), .announced)
        #expect(loading.status == .loading)
        #expect(loading.clockPhase == .notStarted)
        #expect(loading.clockGeneration == 0)

        let running = HubSessionMachine.next(loading, .promptStarted)
        #expect(running.status == .running)
        #expect(running.clockPhase == .ticking)
        #expect(running.clockGeneration == 1)

        let quiet = HubSessionMachine.next(running, .quietForTheStallLimit)
        #expect(quiet.status == .error(.quiet))
        #expect(quiet.clockPhase == .frozen)
        #expect(quiet.clockGeneration == running.clockGeneration)

        let resumed = HubSessionMachine.next(quiet, .activity)
        #expect(resumed.status == .running)
        #expect(resumed.clockPhase == .ticking)
        #expect(resumed.clockGeneration == running.clockGeneration)

        let restarted = HubSessionMachine.next(quiet, .promptStarted)
        #expect(restarted.status == .running)
        #expect(restarted.clockPhase == .ticking)
        #expect(restarted.clockGeneration == running.clockGeneration + 1)

        let failed = HubSessionMachine.next(running, .failed)
        #expect(failed.status == .error(.failed))
        #expect(failed.clockPhase == .frozen)
        #expect(HubSessionMachine.next(failed, .activity) == failed)

        let fromRunning = HubSessionMachine.next(running, .approvalRequested)
        #expect(fromRunning.status == .needsApproval)
        #expect(fromRunning.previous == .running)
        #expect(fromRunning.clockPhase == .ticking)
        #expect(fromRunning.clockGeneration == running.clockGeneration)
        let deniedRunning = HubSessionMachine.next(fromRunning, .denied)
        #expect(deniedRunning.status == .running)
        #expect(deniedRunning.previous == nil)
        #expect(deniedRunning.clockGeneration == running.clockGeneration)

        let waiting = HubSessionMachine.next(running, .questionAsked)
        let fromWaiting = HubSessionMachine.next(waiting, .approvalRequested)
        #expect(fromWaiting.previous == .waitingForInput)
        #expect(HubSessionMachine.next(fromWaiting, .denied).status == .waitingForInput)
        #expect(HubSessionMachine.next(fromWaiting, .timedOut).status == .waitingForInput)
        let approvedWaiting = HubSessionMachine.next(fromWaiting, .approved)
        #expect(approvedWaiting.status == .waitingForInput)
        #expect(approvedWaiting.previous == nil)
        #expect(approvedWaiting.clockGeneration == fromWaiting.clockGeneration)

        let noPrevious = HubSessionState(status: .needsApproval, clockGeneration: 4)
        #expect(HubSessionMachine.next(noPrevious, .denied) == noPrevious)
        #expect(HubSessionMachine.next(noPrevious, .timedOut) == noPrevious)
        let approvedWithNoPrevious = HubSessionMachine.next(noPrevious, .approved)
        #expect(approvedWithNoPrevious.status == .running)
        #expect(approvedWithNoPrevious.previous == nil)
        #expect(approvedWithNoPrevious.clockGeneration == noPrevious.clockGeneration)
    }

    /// ZB-028. Loading accepts a failure and a stall, with the same causes as running.
    @Test func loadingFailureAndStallLeaveLoading() {
        let loading = HubSessionState(status: .loading, clockGeneration: 2)
        let failed = HubSessionMachine.next(loading, .failed)
        #expect(failed.status == .error(.failed))
        #expect(failed.clockPhase == .frozen)
        #expect(failed.clockGeneration == loading.clockGeneration)
        #expect(failed.previous == nil)

        let quiet = HubSessionMachine.next(loading, .quietForTheStallLimit)
        #expect(quiet.status == .error(.quiet))
        #expect(quiet.clockPhase == .frozen)
        #expect(quiet.clockGeneration == loading.clockGeneration)
        #expect(quiet.previous == nil)
    }

    /// ZB-029. Approve restores a session that was waiting for input.
    @Test func approveReturnsToWaitingForInput() {
        let waiting = HubSessionState(status: .waitingForInput, clockGeneration: 3)
        let approval = HubSessionMachine.next(waiting, .approvalRequested)
        #expect(approval.status == .needsApproval)
        #expect(approval.previous == .waitingForInput)
        let approved = HubSessionMachine.next(approval, .approved)
        #expect(approved.status == .waitingForInput)
        #expect(approved.previous == nil)
        #expect(approved.clockGeneration == waiting.clockGeneration)
        #expect(approved.clockPhase == .ticking)

        let running = HubSessionState(status: .running, clockGeneration: 3)
        let fromRunning = HubSessionMachine.next(running, .approvalRequested)
        let approvedRunning = HubSessionMachine.next(fromRunning, .approved)
        #expect(approvedRunning.status == .running)
        #expect(approvedRunning.previous == nil)
        #expect(approvedRunning.clockGeneration == running.clockGeneration)
    }

    /// ZB-034. A failure while an approval is open leaves that state and drops the stored status.
    @Test func failureDuringApprovalLeavesTheApprovalState() {
        let running = HubSessionState(status: .running, clockGeneration: 4)
        let approval = HubSessionMachine.next(running, .approvalRequested)
        #expect(approval.previous == .running)
        let failed = HubSessionMachine.next(approval, .failed)
        #expect(failed.status == .error(.failed))
        #expect(failed.previous == nil)
        #expect(failed.clockGeneration == approval.clockGeneration)
        #expect(failed.clockPhase == .frozen)
    }

    @Test func everyPairFollowsTheSessionTableOrStays() {
        let listed = table.values.reduce(0) { $0 + $1.count }
        #expect(listed == 30)
        #expect(HubSessionStatus.allCases.count == 8)
        #expect(HubSessionEvent.allCases.count == 15)

        for status in HubSessionStatus.allCases {
            for event in HubSessionEvent.allCases {
                let state = seed(status)
                let next = HubSessionMachine.next(state, event)
                #expect(next.clockPhase == next.status.clockPhase)
                if let expected = table[status]?[event] {
                    #expect(next.status == expected.status)
                    #expect(next.previous == expected.previous)
                    #expect(next.clockGeneration == expected.clockGeneration)
                } else {
                    #expect(next == state)
                }
            }
        }
    }

    /// Every status and event is named. There is no default, so a new case fails to compile.
    @Test func everyPairIsNamedInTheTransitionTable() {
        #expect(HubSessionStatus.allCases.count * HubSessionEvent.allCases.count == 120)
        for status in HubSessionStatus.allCases {
            for event in HubSessionEvent.allCases {
                let state = seed(status)
                let next = HubSessionMachine.next(state, event)
                let expected = named(status, event)
                #expect(next.status == expected.status)
                #expect(next.previous == expected.previous)
                #expect(next.clockGeneration == expected.clockGeneration)
            }
        }
    }

    /// Absent, done, and either error have left the in-progress statuses.
    /// From every status and stored previous, some events reach one of those.
    @Test func everyStateCanReachATerminalState() {
        let stored: [HubSessionStatus?] = [nil] + HubSessionStatus.allCases.map { $0 }
        for status in HubSessionStatus.allCases {
            for previous in stored {
                let start = SessionNode(status: status, previous: previous)
                #expect(reachesTerminal(start))
            }
        }
    }

    private struct SessionNode: Hashable {
        var status: HubSessionStatus
        var previous: HubSessionStatus?
    }

    private func isTerminal(_ status: HubSessionStatus) -> Bool {
        switch status {
        case .absent, .done, .error: true
        case .loading, .running, .waitingForInput, .needsApproval: false
        }
    }

    private func reachesTerminal(_ start: SessionNode) -> Bool {
        if isTerminal(start.status) { return true }
        var seen: Set<SessionNode> = [start]
        var queue = [start]
        var index = 0
        while index < queue.count {
            let node = queue[index]
            index += 1
            for event in HubSessionEvent.allCases {
                let next = HubSessionMachine.next(
                    HubSessionState(status: node.status, clockGeneration: 0, previous: node.previous),
                    event
                )
                let reached = SessionNode(status: next.status, previous: next.previous)
                if isTerminal(reached.status) { return true }
                if seen.insert(reached).inserted { queue.append(reached) }
            }
        }
        return false
    }

    /// The seed's stored status is waiting for input, so approve from that seed returns there.
    private func named(_ status: HubSessionStatus, _ event: HubSessionEvent) -> Expectation {
        let stay = Expectation(status: status, previous: .waitingForInput, clockGeneration: 5)
        let gone = Expectation(status: .absent, previous: nil, clockGeneration: 0)
        switch (status, event) {
        case (.absent, .announced):
            return Expectation(status: .loading, previous: nil, clockGeneration: 0)
        case (.absent, .promptStarted),
             (.absent, .ended),
             (.absent, .toolActivity),
             (.absent, .questionAsked),
             (.absent, .approvalRequested),
             (.absent, .finished),
             (.absent, .failed),
             (.absent, .quietForTheStallLimit),
             (.absent, .answerAccepted),
             (.absent, .approved),
             (.absent, .denied),
             (.absent, .timedOut),
             (.absent, .dismissed),
             (.absent, .activity):
            return stay

        case (.loading, .promptStarted):
            return Expectation(status: .running, previous: .waitingForInput, clockGeneration: 6)
        case (.loading, .failed):
            return Expectation(status: .error(.failed), previous: .waitingForInput, clockGeneration: 5)
        case (.loading, .quietForTheStallLimit):
            return Expectation(status: .error(.quiet), previous: .waitingForInput, clockGeneration: 5)
        case (.loading, .ended):
            return gone
        case (.loading, .announced),
             (.loading, .toolActivity),
             (.loading, .questionAsked),
             (.loading, .approvalRequested),
             (.loading, .finished),
             (.loading, .answerAccepted),
             (.loading, .approved),
             (.loading, .denied),
             (.loading, .timedOut),
             (.loading, .dismissed),
             (.loading, .activity):
            return stay

        case (.running, .questionAsked):
            return Expectation(status: .waitingForInput, previous: .waitingForInput, clockGeneration: 5)
        case (.running, .approvalRequested):
            return Expectation(status: .needsApproval, previous: .running, clockGeneration: 5)
        case (.running, .finished):
            return Expectation(status: .done, previous: .waitingForInput, clockGeneration: 5)
        case (.running, .failed):
            return Expectation(status: .error(.failed), previous: .waitingForInput, clockGeneration: 5)
        case (.running, .quietForTheStallLimit):
            return Expectation(status: .error(.quiet), previous: .waitingForInput, clockGeneration: 5)
        case (.running, .ended):
            return gone
        case (.running, .announced),
             (.running, .promptStarted),
             (.running, .toolActivity),
             (.running, .answerAccepted),
             (.running, .approved),
             (.running, .denied),
             (.running, .timedOut),
             (.running, .dismissed),
             (.running, .activity):
            return stay

        case (.waitingForInput, .answerAccepted):
            return Expectation(status: .running, previous: .waitingForInput, clockGeneration: 5)
        case (.waitingForInput, .approvalRequested):
            return Expectation(status: .needsApproval, previous: .waitingForInput, clockGeneration: 5)
        case (.waitingForInput, .finished):
            return Expectation(status: .done, previous: .waitingForInput, clockGeneration: 5)
        case (.waitingForInput, .failed):
            return Expectation(status: .error(.failed), previous: .waitingForInput, clockGeneration: 5)
        case (.waitingForInput, .ended):
            return gone
        case (.waitingForInput, .announced),
             (.waitingForInput, .promptStarted),
             (.waitingForInput, .toolActivity),
             (.waitingForInput, .questionAsked),
             (.waitingForInput, .quietForTheStallLimit),
             (.waitingForInput, .approved),
             (.waitingForInput, .denied),
             (.waitingForInput, .timedOut),
             (.waitingForInput, .dismissed),
             (.waitingForInput, .activity):
            return stay

        case (.needsApproval, .approved),
             (.needsApproval, .denied),
             (.needsApproval, .timedOut):
            return Expectation(status: .waitingForInput, previous: nil, clockGeneration: 5)
        case (.needsApproval, .failed):
            return Expectation(status: .error(.failed), previous: nil, clockGeneration: 5)
        case (.needsApproval, .ended):
            return gone
        case (.needsApproval, .announced),
             (.needsApproval, .promptStarted),
             (.needsApproval, .toolActivity),
             (.needsApproval, .questionAsked),
             (.needsApproval, .approvalRequested),
             (.needsApproval, .finished),
             (.needsApproval, .quietForTheStallLimit),
             (.needsApproval, .answerAccepted),
             (.needsApproval, .dismissed),
             (.needsApproval, .activity):
            return stay

        case (.done, .promptStarted):
            return Expectation(status: .running, previous: .waitingForInput, clockGeneration: 6)
        case (.done, .ended):
            return gone
        case (.done, .announced),
             (.done, .toolActivity),
             (.done, .questionAsked),
             (.done, .approvalRequested),
             (.done, .finished),
             (.done, .failed),
             (.done, .quietForTheStallLimit),
             (.done, .answerAccepted),
             (.done, .approved),
             (.done, .denied),
             (.done, .timedOut),
             (.done, .dismissed),
             (.done, .activity):
            return stay

        case (.error(.quiet), .activity):
            return Expectation(status: .running, previous: .waitingForInput, clockGeneration: 5)
        case (.error(.quiet), .promptStarted):
            return Expectation(status: .running, previous: .waitingForInput, clockGeneration: 6)
        case (.error(.quiet), .ended):
            return gone
        case (.error(.quiet), .announced),
             (.error(.quiet), .toolActivity),
             (.error(.quiet), .questionAsked),
             (.error(.quiet), .approvalRequested),
             (.error(.quiet), .finished),
             (.error(.quiet), .failed),
             (.error(.quiet), .quietForTheStallLimit),
             (.error(.quiet), .answerAccepted),
             (.error(.quiet), .approved),
             (.error(.quiet), .denied),
             (.error(.quiet), .timedOut),
             (.error(.quiet), .dismissed):
            return stay

        case (.error(.failed), .promptStarted):
            return Expectation(status: .running, previous: .waitingForInput, clockGeneration: 6)
        case (.error(.failed), .dismissed):
            return Expectation(status: .done, previous: .waitingForInput, clockGeneration: 5)
        case (.error(.failed), .ended):
            return gone
        case (.error(.failed), .announced),
             (.error(.failed), .toolActivity),
             (.error(.failed), .questionAsked),
             (.error(.failed), .approvalRequested),
             (.error(.failed), .finished),
             (.error(.failed), .failed),
             (.error(.failed), .quietForTheStallLimit),
             (.error(.failed), .answerAccepted),
             (.error(.failed), .approved),
             (.error(.failed), .denied),
             (.error(.failed), .timedOut),
             (.error(.failed), .activity):
            return stay
        }
    }
}
