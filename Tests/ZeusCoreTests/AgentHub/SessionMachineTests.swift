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
            .approved: Expectation(status: .running, previous: nil, clockGeneration: 5),
            .denied: Expectation(status: .waitingForInput, previous: nil, clockGeneration: 5),
            .timedOut: Expectation(status: .waitingForInput, previous: nil, clockGeneration: 5),
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
        #expect(HubSessionMachine.next(fromWaiting, .approved).status == .running)

        let noPrevious = HubSessionState(status: .needsApproval, clockGeneration: 4)
        #expect(HubSessionMachine.next(noPrevious, .denied) == noPrevious)
        #expect(HubSessionMachine.next(noPrevious, .timedOut) == noPrevious)
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
        #expect(listed == 27)
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
}
