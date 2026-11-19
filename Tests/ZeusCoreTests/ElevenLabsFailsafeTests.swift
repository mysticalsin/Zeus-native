import Foundation
import Testing
@testable import ZeusCore

@Suite("ElevenLabs failsafe: pause bookkeeping and deadline decisions")
struct ElevenLabsFailsafeTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    // MARK: Pause bookkeeping

    @Test func aBadKeyOrEmptyCreditsPauseFifteenMinutesAndExpire() {
        for code in [401, 402] {
            var pause = ElevenLabsPause()
            pause.note(.status(code), now: now)
            #expect(pause.persistedUntil == now.addingTimeInterval(900))
            #expect(pause.isPaused(now: now.addingTimeInterval(899)))
            #expect(!pause.isPaused(now: now.addingTimeInterval(900)))
        }
    }

    @Test func aRateLimitOrServerErrorPausesOneMinute() {
        for code in [429, 500, 503] {
            var pause = ElevenLabsPause()
            pause.note(.status(code), now: now)
            #expect(pause.isPaused(now: now.addingTimeInterval(59)))
            #expect(!pause.isPaused(now: now.addingTimeInterval(60)))
        }
    }

    @Test func anUnreachableRequestPausesOneMinuteInMemoryOnly() {
        var pause = ElevenLabsPause()
        pause.note(.unreachable, now: now)
        #expect(pause.persistedUntil == nil)
        #expect(pause.transientUntil == now.addingTimeInterval(60))
        #expect(pause.isPaused(now: now.addingTimeInterval(59)))
        #expect(!pause.isPaused(now: now.addingTimeInterval(61)))
    }

    @Test func aTransientPauseNeverShortensALongerPersistedOne() {
        var pause = ElevenLabsPause()
        pause.note(.status(402), now: now)
        pause.note(.unreachable, now: now.addingTimeInterval(10))
        #expect(pause.isPaused(now: now.addingTimeInterval(600)))
    }

    @Test func aLaterShortPauseNeverShortensALongRefusalPause() {
        var pause = ElevenLabsPause()
        pause.note(.status(402), now: now)
        pause.note(.status(429), now: now.addingTimeInterval(10))
        #expect(pause.persistedUntil == now.addingTimeInterval(900))
    }

    @Test func aStreamThatPlayedClearsBothPauses() {
        var pause = ElevenLabsPause()
        pause.note(.status(401), now: now)
        pause.note(.unreachable, now: now)
        pause.clear()
        #expect(!pause.isPaused(now: now))
    }

    @Test func aStoredPersistedPauseStillExpiresAfterARestart() {
        let pause = ElevenLabsPause(persistedUntil: now.addingTimeInterval(30))
        #expect(pause.isPaused(now: now))
        #expect(!pause.isPaused(now: now.addingTimeInterval(31)))
    }

    // MARK: Deadline decisions

    @Test func theDeadlineBoundsHeadersAndFirstAudioTogether() {
        #expect(ElevenLabsFailsafe.firstAudioRemaining(began: now, now: now) == 4)
        #expect(ElevenLabsFailsafe.firstAudioRemaining(began: now, now: now.addingTimeInterval(3.5)) == 0.5)
        #expect(ElevenLabsFailsafe.firstAudioRemaining(began: now, now: now.addingTimeInterval(4)) == nil)
        #expect(ElevenLabsFailsafe.firstAudioRemaining(began: now, now: now.addingTimeInterval(15)) == nil)
    }

    @Test func noFurtherRouteIsTriedOnceTheDeadlinePassed() {
        #expect(ElevenLabsFailsafe.shouldTryNextRoute(remaining: 1.5))
        #expect(!ElevenLabsFailsafe.shouldTryNextRoute(remaining: nil))
    }

    @Test func theFastModelRetryIsSkippedWhenPausedOrPastTheDeadline() {
        #expect(ElevenLabsFailsafe.shouldRetryOnFastModel(paused: false, remaining: 2, answerHadAudio: false))
        #expect(!ElevenLabsFailsafe.shouldRetryOnFastModel(paused: true, remaining: 2, answerHadAudio: false))
        #expect(!ElevenLabsFailsafe.shouldRetryOnFastModel(paused: false, remaining: nil, answerHadAudio: false))
        #expect(!ElevenLabsFailsafe.shouldRetryOnFastModel(paused: false, remaining: 2, answerHadAudio: true))
    }

    @Test func aPartialChunkAtTheDeadlineIsDiscarded() {
        #expect(ElevenLabsFailsafe.shouldPushPartialChunk(remaining: 1))
        #expect(!ElevenLabsFailsafe.shouldPushPartialChunk(remaining: nil))
    }

    // MARK: Import must not pin an engine

    @Test func anImportedProviderWithoutAnExplicitAutoFlagStaysAutomatic() {
        #expect(ElevenLabsFailsafe.defaultEngineAuto(explicit: nil, storedProvider: "kokoro"))
        #expect(ElevenLabsFailsafe.defaultEngineAuto(explicit: nil, storedProvider: nil))
        #expect(!ElevenLabsFailsafe.defaultEngineAuto(explicit: false, storedProvider: "kokoro"))
        #expect(ElevenLabsFailsafe.defaultEngineAuto(explicit: true, storedProvider: "elevenLabs"))
    }
}
