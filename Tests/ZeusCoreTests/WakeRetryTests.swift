import Testing
import ZeusCore

@Suite("Wake word retry")
struct WakeRetryTests {
    private typealias W = WakeRetry

    private func fail(_ failure: W.Failure, times: Int, from start: W.State = .ready, at now: Double = 0) -> (W.State, [[W.Effect]]) {
        var state = start
        var all: [[W.Effect]] = []
        var clock = now
        for _ in 0..<times {
            let (next, effects) = W.reduce(state, .failed(failure, now: clock))
            state = next
            all.append(effects)
            if case .backingOff(_, _, let retryAt) = next { clock = retryAt }
        }
        return (state, all)
    }

    @Test func readyMayTryImmediately() {
        #expect(W.canTry(.ready, now: 0))
    }

    @Test func aMicrophoneFailureWaitsTenSecondsThenDoublesUpToACap() {
        var state = W.State.ready
        var delays: [Double] = []
        var clock = 100.0
        for _ in 0..<5 {
            state = W.reduce(state, .failed(.microphone, now: clock)).0
            guard case .backingOff(_, _, let retryAt) = state else { Issue.record("expected backoff"); return }
            delays.append(retryAt - clock)
            #expect(!W.canTry(state, now: retryAt - 0.1))
            #expect(W.canTry(state, now: retryAt))
            clock = retryAt
        }
        #expect(delays == [10, 20, 40, 60, 60])
    }

    @Test func retriesAreBoundedThenNeedAttentionAndNothingStartsAgain() {
        let (state, effects) = fail(.microphone, times: 6)
        #expect(state == .needsAttention(.microphone))
        #expect(effects[5].contains(.gaveUp(.microphone)))
        #expect(!W.canTry(state, now: 1_000_000))
    }

    @Test func missingOnDeviceRecognitionGivesUpAfterThreeTries() {
        let (state, effects) = fail(.onDeviceRecognition, times: 3)
        #expect(state == .needsAttention(.onDeviceRecognition))
        #expect(effects[2].contains(.gaveUp(.onDeviceRecognition)))
    }

    @Test func theSameFailureIsLoggedOncePerStreak() {
        let (_, effects) = fail(.microphone, times: 4)
        #expect(effects[0] == [.logFailure(.microphone)])
        #expect(effects[1].isEmpty && effects[2].isEmpty && effects[3].isEmpty)
    }

    @Test func aDifferentFailureStartsANewStreakAndIsLogged() {
        let (afterMic, _) = fail(.microphone, times: 2)
        let (state, effects) = W.reduce(afterMic, .failed(.onDeviceRecognition, now: 500))
        #expect(effects == [.logFailure(.onDeviceRecognition)])
        #expect(state == .backingOff(failure: .onDeviceRecognition, attempts: 1, retryAt: 530))
    }

    @Test func aFailureWhileGivenUpChangesNothing() {
        let (state, effects) = W.reduce(.needsAttention(.microphone), .failed(.microphone, now: 9))
        #expect(state == .needsAttention(.microphone))
        #expect(effects.isEmpty)
    }

    @Test func successOrAChangeStartsOver() {
        #expect(W.reduce(.backingOff(failure: .microphone, attempts: 3, retryAt: 99), .started).0 == .ready)
        #expect(W.reduce(.needsAttention(.microphone), .reset).0 == .ready)
        let (again, effects) = fail(.microphone, times: 1, from: .ready)
        #expect(again == .backingOff(failure: .microphone, attempts: 1, retryAt: 10))
        #expect(effects[0] == [.logFailure(.microphone)])
    }
}
