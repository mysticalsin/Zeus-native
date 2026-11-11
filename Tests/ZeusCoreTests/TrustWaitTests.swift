import Testing
import ZeusCore

@Suite("Accessibility wait list")
struct TrustWaitTests {
    private typealias T = TrustWait

    private func run(_ events: [T.Event]) -> (state: T.State, effects: [[T.Effect]]) {
        var state = T.State()
        var all: [[T.Effect]] = []
        for event in events {
            let (next, effects) = T.reduce(state, event)
            state = next
            all.append(effects)
        }
        return (state, all)
    }

    @Test func whenAlreadyTrustedTheFeatureRunsAtOnceAndNothingPolls() {
        let (state, effects) = run([.wanted(key: "a", trusted: true)])
        #expect(effects[0] == [.run(key: "a")])
        #expect(state == T.State())
    }

    @Test func theFirstWaiterStartsThePollAndLaterOnesJoinIt() {
        let (state, effects) = run([.wanted(key: "a", trusted: false), .wanted(key: "b", trusted: false)])
        #expect(effects[0] == [.startPolling])
        #expect(effects[1].isEmpty)
        #expect(state.waiting == ["a", "b"])
    }

    @Test func askingTwiceUnderTheSameKeyStartsTheFeatureOnce() {
        let (state, effects) = run([.wanted(key: "hud", trusted: false), .wanted(key: "hud", trusted: false), .becameTrusted])
        #expect(state.waiting.isEmpty)
        #expect(effects[2] == [.stopPolling, .run(key: "hud")])
    }

    @Test func grantingRunsEveryWaiterInOrderAndStopsThePoll() {
        let (state, effects) = run([.wanted(key: "a", trusted: false), .wanted(key: "b", trusted: false), .becameTrusted])
        #expect(effects[2] == [.stopPolling, .run(key: "a"), .run(key: "b")])
        #expect(!state.polling)
    }

    @Test func aFeatureTurnedOffWhileWaitingIsNeverStartedLater() {
        let (state, effects) = run([.wanted(key: "a", trusted: false), .wanted(key: "b", trusted: false),
                                    .cancelled(key: "a"), .becameTrusted])
        #expect(effects[2].isEmpty, "b still waits, so the poll continues")
        #expect(effects[3] == [.stopPolling, .run(key: "b")])
        #expect(state.waiting.isEmpty)
    }

    @Test func theLastCancelStopsThePollSoItDoesNotRunForever() {
        let (state, effects) = run([.wanted(key: "a", trusted: false), .cancelled(key: "a")])
        #expect(effects[1] == [.stopPolling])
        #expect(!state.polling)
    }

    @Test func cancellingAnUnknownKeyOrBecomingTrustedWithNobodyWaitingDoesNothing() {
        let (_, effects) = run([.cancelled(key: "x"), .becameTrusted])
        #expect(effects[0].isEmpty && effects[1].isEmpty)
    }

    @Test func aFeatureThatAsksAgainAfterBeingServedWaitsAgain() {
        let (state, effects) = run([.wanted(key: "a", trusted: false), .becameTrusted, .wanted(key: "a", trusted: false)])
        #expect(effects[2] == [.startPolling])
        #expect(state.waiting == ["a"])
    }
}
