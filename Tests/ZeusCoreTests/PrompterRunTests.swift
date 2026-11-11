import Testing
import ZeusCore

@Suite("Teleprompter run")
struct PrompterRunTests {
    private typealias P = PrompterRun

    @Test func beginWithVoiceFollowStartsTheMicWithItsSession() {
        let (state, effects) = P.reduce(.idle, .began(voiceFollow: true, session: 1))
        #expect(state == .running(mic: 1))
        #expect(effects == [.startMic(session: 1)])
    }

    @Test func beginWithoutVoiceFollowStartsNoMic() {
        let (state, effects) = P.reduce(.idle, .began(voiceFollow: false, session: 1))
        #expect(state == .running(mic: nil))
        #expect(effects.isEmpty)
    }

    @Test func aSecondBeginWhileRunningChangesNothing() {
        let (state, effects) = P.reduce(.running(mic: 1), .began(voiceFollow: true, session: 2))
        #expect(state == .running(mic: 1))
        #expect(effects.isEmpty)
    }

    @Test func aLevelQueuedBeforeEndCannotLandAfterIt() {
        // The meter used to light again after end() reset it to zero.
        let (ended, effects) = P.reduce(.running(mic: 1), .ended)
        #expect(ended == .idle)
        #expect(effects == [.stopMic])
        #expect(!ended.acceptsLevel(from: 1))
    }

    @Test func aLevelFromAnEarlierMicSessionIsRejectedAfterVoiceFollowToggles() {
        let (off, offEffects) = P.reduce(.running(mic: 1), .voiceChanged(on: false, session: 2))
        #expect(offEffects == [.stopMic])
        #expect(!off.acceptsLevel(from: 1))
        let (on, onEffects) = P.reduce(off, .voiceChanged(on: true, session: 3))
        #expect(onEffects == [.startMic(session: 3)])
        #expect(!on.acceptsLevel(from: 1), "the first mic's queued level must not reach the second session")
        #expect(on.acceptsLevel(from: 3))
    }

    @Test func voiceChangesWhileIdleOrAlreadyInThatStateDoNothing() {
        #expect(P.reduce(.idle, .voiceChanged(on: true, session: 1)).1.isEmpty)
        #expect(P.reduce(.running(mic: 1), .voiceChanged(on: true, session: 2)).1.isEmpty)
        #expect(P.reduce(.running(mic: nil), .voiceChanged(on: false, session: 2)).1.isEmpty)
    }

    @Test func aMicFailureFallsBackToSteadyScrollingOnlyForTheLiveSession() {
        let (state, effects) = P.reduce(.running(mic: 2), .micFailed(session: 2))
        #expect(state == .running(mic: nil))
        #expect(effects == [.stopMic])
        let (same, none) = P.reduce(.running(mic: 3), .micFailed(session: 2))
        #expect(same == .running(mic: 3) && none.isEmpty)
    }

    @Test func endWithoutAMicHasNothingToStopAndIdleEndIsHarmless() {
        let (first, firstEffects) = P.reduce(.running(mic: nil), .ended)
        #expect(first == .idle && firstEffects.isEmpty)
        let (second, secondEffects) = P.reduce(.idle, .ended)
        #expect(second == .idle && secondEffects.isEmpty)
    }
}
