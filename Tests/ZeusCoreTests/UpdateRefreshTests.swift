import Testing
import ZeusCore

@Suite("Update badge refresh ordering")
struct UpdateRefreshTests {
    private typealias U = UpdateRefresh

    @Test func firstRequestStartsAFetch() {
        let (state, effects) = U.reduce(.idle, .requested(token: 1))
        #expect(state == .refreshing(token: 1))
        #expect(effects == [.startFetch(token: 1)])
    }

    @Test func aNewerRequestSupersedesAndCancelsTheOlderFetch() {
        let (state, effects) = U.reduce(.refreshing(token: 1), .requested(token: 2))
        #expect(state == .refreshing(token: 2))
        #expect(effects == [.cancelFetch(token: 1), .startFetch(token: 2)])
    }

    @Test func liveCompletionAppliesAndReturnsToIdle() {
        let (state, effects) = U.reduce(.refreshing(token: 3), .completed(token: 3))
        #expect(state == .idle)
        #expect(effects == [.apply(token: 3)])
    }

    @Test func slowOlderCheckFinishingLateCannotBringTheBadgeBack() {
        // The person turns auto-update off (request 2) while request 1 is still on the network.
        let (second, _) = U.reduce(.refreshing(token: 1), .requested(token: 2))
        let (afterNewer, applyNewer) = U.reduce(second, .completed(token: 2))
        #expect(applyNewer == [.apply(token: 2)])
        let (afterStale, applyStale) = U.reduce(afterNewer, .completed(token: 1))
        #expect(afterStale == .idle)
        #expect(applyStale.isEmpty)
    }

    @Test func staleCompletionWhileNewerIsRunningIsIgnored() {
        let (state, effects) = U.reduce(.refreshing(token: 5), .completed(token: 4))
        #expect(state == .refreshing(token: 5))
        #expect(effects.isEmpty)
    }

    @Test func completionWhileIdleIsIgnored() {
        let (state, effects) = U.reduce(.idle, .completed(token: 1))
        #expect(state == .idle)
        #expect(effects.isEmpty)
    }

    @Test func invalidateFromRefreshingCancelsTheFetch() {
        let (state, effects) = U.reduce(.refreshing(token: 6), .invalidated)
        #expect(state == .idle)
        #expect(effects == [.cancelFetch(token: 6)])
    }

    @Test func invalidateFromIdleDoesNothing() {
        let (state, effects) = U.reduce(.idle, .invalidated)
        #expect(state == .idle)
        #expect(effects.isEmpty)
    }

    @Test func completionAfterInvalidateIsDropped() {
        let (invalidated, _) = U.reduce(.refreshing(token: 7), .invalidated)
        let (state, effects) = U.reduce(invalidated, .completed(token: 7))
        #expect(state == .idle)
        #expect(effects.isEmpty)
    }

    @Test func requestAfterCompletionStartsFresh() {
        let (idle, _) = U.reduce(.refreshing(token: 1), .completed(token: 1))
        let (state, effects) = U.reduce(idle, .requested(token: 2))
        #expect(state == .refreshing(token: 2))
        #expect(effects == [.startFetch(token: 2)])
    }
}
