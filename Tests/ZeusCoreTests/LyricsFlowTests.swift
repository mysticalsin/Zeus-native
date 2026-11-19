import Foundation
import Testing
@testable import ZeusCore

/// The lyrics store's load, retry and lookup decisions, driven as events with a fixed clock. No network, no cache,
/// no task: the effects are what the store would run.
@Suite struct LyricsFlowTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let song = LyricsFlow.Track(key: "song")
    private let lines = [LyricLine(time: 1, text: "one")]

    /// A flow that is loading `song`.
    private func loading() -> LyricsFlow {
        var flow = LyricsFlow()
        _ = flow.reduce(.viewerAppeared)
        _ = flow.reduce(.load(enabled: true, track: song, now: t0))
        _ = flow.reduce(.cacheRead(key: "song", cached: nil, mayAsk: true, now: t0))
        return flow
    }

    /// A flow whose lookup for `song` failed at `t0`.
    private func failed(retryAfter: TimeInterval? = nil) -> LyricsFlow {
        var flow = loading()
        _ = flow.reduce(.failed(key: "song", retryAfter: retryAfter, now: t0))
        return flow
    }

    // MARK: Load

    @Test func aNewTrackCancelsTheOldWorkAndReadsTheCache() {
        var flow = LyricsFlow()
        let effects = flow.reduce(.load(enabled: true, track: song, now: t0))
        #expect(effects == [.cancelLookup, .cancelRetry, .readCache])
        #expect(flow.key == "song")
        #expect(flow.phase == .idle)
    }

    @Test func aCachedAnswerIsShownWithoutAskingTheService() {
        var flow = LyricsFlow()
        _ = flow.reduce(.load(enabled: true, track: song, now: t0))
        let effects = flow.reduce(.cacheRead(key: "song", cached: .synced(lines), mayAsk: true, now: t0))
        #expect(effects.isEmpty)
        #expect(flow.phase == .answered(.synced(lines)))
    }

    @Test func aCachedMissIsShownWithoutAskingTheService() {
        var flow = LyricsFlow()
        _ = flow.reduce(.load(enabled: true, track: song, now: t0))
        #expect(flow.reduce(.cacheRead(key: "song", cached: LyricsResult.none, mayAsk: true, now: t0)).isEmpty)
        #expect(flow.phase == .answered(.none))
    }

    @Test func noCacheEntryStartsTheLookup() {
        var flow = LyricsFlow()
        _ = flow.reduce(.load(enabled: true, track: song, now: t0))
        #expect(flow.reduce(.cacheRead(key: "song", cached: nil, mayAsk: true, now: t0)) == [.sendLookup])
        #expect(flow.phase == .loading)
    }

    @Test func nothingIsSentWhereAskingIsNotAllowed() {
        var flow = LyricsFlow()
        _ = flow.reduce(.load(enabled: true, track: song, now: t0))
        #expect(flow.reduce(.cacheRead(key: "song", cached: nil, mayAsk: false, now: t0)).isEmpty)
        #expect(flow.phase == .answered(.none))
    }

    @Test func aTrackThatCannotBeAskedAboutHasNoLyricsAndReadsNoCache() {
        var flow = LyricsFlow()
        let effects = flow.reduce(.load(enabled: true, track: LyricsFlow.Track(key: "x", isAskable: false), now: t0))
        #expect(effects == [.cancelLookup, .cancelRetry])
        #expect(flow.phase == .answered(.none))
    }

    @Test func aStaleCacheReadIsIgnored() {
        var flow = LyricsFlow()
        _ = flow.reduce(.load(enabled: true, track: song, now: t0))
        _ = flow.reduce(.load(enabled: true, track: LyricsFlow.Track(key: "next"), now: t0))
        #expect(flow.reduce(.cacheRead(key: "song", cached: .synced(lines), mayAsk: true, now: t0)).isEmpty)
        #expect(flow.phase == .idle)
        #expect(flow.key == "next")
    }

    @Test func loadingTheSameTrackAgainDoesNothingWhileItLoads() {
        var flow = loading()
        #expect(flow.reduce(.load(enabled: true, track: song, now: t0)).isEmpty)
        #expect(flow.phase == .loading)
    }

    @Test func nothingPlayingDropsTheTrackAndStopsTheWork() {
        var flow = loading()
        let effects = flow.reduce(.load(enabled: true, track: nil, now: t0))
        #expect(effects == [.cancelLookup, .cancelRetry])
        #expect(flow.key == nil)
        #expect(flow.isPlaying == false)
    }

    // MARK: Answers

    @Test func anAnswerIsCachedAndClearsTheWait() {
        var flow = failed()
        _ = flow.reduce(.load(enabled: true, track: LyricsFlow.Track(key: "next"), now: t0.addingTimeInterval(60)))
        _ = flow.reduce(.cacheRead(key: "next", cached: nil, mayAsk: true, now: t0.addingTimeInterval(60)))
        let effects = flow.reduce(.answered(key: "next", .synced(lines)))
        #expect(effects == [.saveCache(.synced(lines))])
        #expect(flow.phase == .answered(.synced(lines)))
        #expect(flow.backoff.failures == 0)
    }

    @Test func aMissOnEveryStepIsCachedAsAnAnswer() {
        var flow = loading()
        #expect(flow.reduce(.answered(key: "song", .none)) == [.saveCache(.none)])
        #expect(flow.phase == .answered(.none))
    }

    @Test func aStaleAnswerIsNeitherShownNorCached() {
        var flow = loading()
        _ = flow.reduce(.load(enabled: true, track: LyricsFlow.Track(key: "next"), now: t0))
        #expect(flow.reduce(.answered(key: "song", .synced(lines))).isEmpty)
        #expect(flow.phase == .idle)
        #expect(flow.reduce(.failed(key: "song", retryAfter: nil, now: t0)).isEmpty)
        #expect(flow.backoff.failures == 0)
    }

    // MARK: Failures

    @Test func aFailureIsNeverCachedAndArmsTheRetry() {
        var flow = loading()
        let effects = flow.reduce(.failed(key: "song", retryAfter: nil, now: t0))
        #expect(effects == [.scheduleRetry])
        #expect(!effects.contains { if case .saveCache = $0 { true } else { false } })
        #expect(flow.phase == .unavailable)
        #expect(flow.retryArmed)
        #expect(flow.backoff.remaining(now: t0) == LyricsBackoff.firstDelay)
    }

    @Test func aNewTrackDuringTheWaitShowsUnavailableAndSendsNothing() {
        var flow = failed()
        let later = t0.addingTimeInterval(5)
        _ = flow.reduce(.load(enabled: true, track: LyricsFlow.Track(key: "next"), now: later))
        let effects = flow.reduce(.cacheRead(key: "next", cached: nil, mayAsk: true, now: later))
        #expect(effects == [.scheduleRetry])
        #expect(flow.phase == .unavailable)
        #expect(flow.retryArmed)
    }

    // MARK: Retry

    @Test func theRetryAsksOnceWhenTheWaitIsOver() {
        var flow = failed()
        let over = t0.addingTimeInterval(LyricsBackoff.firstDelay)
        #expect(flow.retryPlan(for: "song", now: t0, enabled: true) == .wait(LyricsBackoff.firstDelay))
        #expect(flow.retryPlan(for: "song", now: over, enabled: true) == .askNow)
        #expect(flow.reduce(.retryDue(key: "song", now: over)) == [.sendLookup])
        #expect(flow.phase == .loading)
        #expect(!flow.retryArmed)
    }

    @Test func theRetryStopsWhenNothingPlaysOrNoViewIsOnScreenOrLyricsAreOff() {
        var flow = failed()
        #expect(flow.retryPlan(for: "song", now: t0, enabled: false) == .stop)
        #expect(flow.retryPlan(for: "other", now: t0, enabled: true) == .stop)
        _ = flow.reduce(.load(enabled: true, track: LyricsFlow.Track(key: "song", isPlaying: false), now: t0))
        #expect(flow.retryPlan(for: "song", now: t0, enabled: true) == .stop)
        _ = flow.reduce(.load(enabled: true, track: song, now: t0))
        #expect(flow.retryPlan(for: "song", now: t0, enabled: true) == .wait(LyricsBackoff.firstDelay))
        _ = flow.reduce(.viewerLeft)
        #expect(flow.retryPlan(for: "song", now: t0, enabled: true) == .stop)
    }

    @Test func aRetryForAnotherTrackIsIgnored() {
        var flow = failed()
        _ = flow.reduce(.load(enabled: true, track: LyricsFlow.Track(key: "next"), now: t0))
        #expect(flow.reduce(.retryDue(key: "song", now: t0.addingTimeInterval(60))).isEmpty)
    }

    @Test func aStoppedRetryStartsOverWhenTheSameTrackPlaysAgain() {
        var flow = failed()
        _ = flow.reduce(.retryStopped)
        #expect(!flow.retryArmed)
        let over = t0.addingTimeInterval(LyricsBackoff.firstDelay)
        // Paused: nothing starts.
        #expect(flow.reduce(.load(enabled: true, track: LyricsFlow.Track(key: "song", isPlaying: false), now: over)).isEmpty)
        // Playing again and the wait is over: the request goes out.
        #expect(flow.reduce(.load(enabled: true, track: song, now: over)) == [.sendLookup])
        #expect(flow.phase == .loading)
    }

    @Test func aStoppedRetryStartsOverButStillWaitsOutTheBackoff() {
        var flow = failed()
        _ = flow.reduce(.retryStopped)
        #expect(flow.reduce(.load(enabled: true, track: song, now: t0.addingTimeInterval(1))) == [.scheduleRetry])
        #expect(flow.phase == .unavailable)
        #expect(flow.retryArmed)
    }

    @Test func anArmedRetryIsNotStartedAgainByTheSameTrack() {
        var flow = failed()
        #expect(flow.retryArmed)
        #expect(flow.reduce(.load(enabled: true, track: song, now: t0.addingTimeInterval(100))).isEmpty)
    }

    // MARK: Viewers

    @Test func theLastViewerLeavingCancelsTheRetry() {
        var flow = failed()
        _ = flow.reduce(.viewerAppeared)
        #expect(flow.reduce(.viewerLeft).isEmpty)
        #expect(flow.reduce(.viewerLeft) == [.cancelRetry])
        #expect(!flow.retryArmed)
        #expect(flow.reduce(.viewerLeft) == [.cancelRetry])
        #expect(flow.viewers == 0)
    }

    // MARK: The privacy switch

    @Test func switchingLyricsOffCancelsTheLookupAndTheRetry() {
        var flow = loading()
        #expect(flow.reduce(.privacyOff) == [.cancelLookup, .cancelRetry])
        #expect(flow.phase == .off)
        #expect(flow.key == nil)
        var waiting = failed()
        #expect(waiting.reduce(.privacyOff) == [.cancelLookup, .cancelRetry])
        #expect(!waiting.retryArmed)
    }

    @Test func noStepGoesOutOnceTheSwitchIsOff() {
        var flow = loading()
        #expect(flow.accepts(key: "song", enabled: true))
        #expect(!flow.accepts(key: "song", enabled: false))
        _ = flow.reduce(.privacyOff)
        #expect(!flow.accepts(key: "song", enabled: true))
        // A reply that arrives after the switch went off is neither shown nor cached.
        #expect(flow.reduce(.answered(key: "song", .synced(lines))).isEmpty)
        #expect(flow.reduce(.failed(key: "song", retryAfter: nil, now: t0)).isEmpty)
        #expect(flow.phase == .off)
    }

    @Test func aLoadWithTheSwitchOffTurnsEverythingOff() {
        var flow = loading()
        #expect(flow.reduce(.load(enabled: false, track: song, now: t0)) == [.cancelLookup, .cancelRetry])
        #expect(flow.phase == .off)
        // Switched back on, the same track is looked up again.
        #expect(flow.reduce(.load(enabled: true, track: song, now: t0)) == [.cancelLookup, .cancelRetry, .readCache])
    }

    @Test func aStepIsOnlyAcceptedForTheCurrentLoadingTrack() {
        var flow = loading()
        #expect(!flow.accepts(key: "other", enabled: true))
        _ = flow.reduce(.answered(key: "song", .none))
        #expect(!flow.accepts(key: "song", enabled: true))
    }

    // MARK: Seeding

    @Test func aSeededAnswerIsShownForItsTrack() {
        var flow = LyricsFlow()
        #expect(flow.reduce(.seeded(key: "song", .plain("la"))).isEmpty)
        #expect(flow.key == "song")
        #expect(flow.phase == .answered(.plain("la")))
    }
}
