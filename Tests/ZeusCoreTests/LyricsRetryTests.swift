import Foundation
import Testing
@testable import ZeusCore

/// When the lyrics wait is over, may the one retry go out? Only for the track that is still current, while it
/// plays, with a lyric view on screen, and with lyrics still switched on. No clock, no network.
@Suite struct LyricsRetryTests {
    private func plan(remaining: TimeInterval = 0, sameTrack: Bool = true, isPlaying: Bool = true,
                      visible: Bool = true, enabled: Bool = true) -> LyricsRetryPlan {
        LyricsRetry.plan(remaining: remaining, sameTrack: sameTrack, isPlaying: isPlaying, visible: visible, enabled: enabled)
    }

    @Test func asksOnceWhenTheWaitIsOverAndEverythingStillHolds() {
        #expect(plan() == .askNow)
    }

    @Test func waitsWhileTheBackoffRuns() {
        #expect(plan(remaining: 30) == .wait(30))
        #expect(plan(remaining: 0.5) == .wait(0.5))
    }

    @Test func stopsWhenTheTrackIsNoLongerTheCurrentOne() {
        #expect(plan(sameTrack: false) == .stop)
        #expect(plan(remaining: 30, sameTrack: false) == .stop)
    }

    @Test func stopsWhenNothingIsPlaying() {
        #expect(plan(isPlaying: false) == .stop)
        #expect(plan(remaining: 900, isPlaying: false) == .stop)
    }

    @Test func stopsWhenNoLyricViewIsOnScreen() {
        #expect(plan(visible: false) == .stop)
        #expect(plan(remaining: 900, visible: false) == .stop)
    }

    @Test func stopsWhenLyricsWereSwitchedOff() {
        #expect(plan(enabled: false) == .stop)
        #expect(plan(remaining: 30, enabled: false) == .stop)
    }

    @Test func aNegativeWaitCountsAsOver() {
        #expect(plan(remaining: -1) == .askNow)
    }
}
